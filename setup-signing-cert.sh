#!/usr/bin/env bash
# setup-signing-cert.sh — create a persistent self-signed identity so
# glance's codesign identifier stays stable across rebuilds. Same OpenSSL 3
# + security(1) approach as facet / chord / perch.
#
# glance doesn't need Accessibility permission, so TCC retention isn't the
# motivation here. But keeping the family signing flow uniform means the
# same identity (`glance-dev`) is reusable, and a future feature that needs
# stable identity (e.g. Hardened Runtime / notarization rehearsal) just
# works.

set -euo pipefail
cd "$(dirname "$0")"

CN="glance-dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# `security import` leaves the key's partition list at `apple-tool:`, which keeps
# codesign out: the first signature fails with errSecInternalComponent over ssh
# and stops at a SecurityAgent dialog in a GUI session, so an unattended rebuild
# hangs (chord's script, Tart VM, macOS 26.5, 2026-11-07).
#
# A usable key stays a silent no-op: the family's unattended callers (capsule's
# verify.sh, the tap formulas) run this script with its output in a log and stop
# the run if it fails. glance has no such caller today; the script keeps the
# family's shape so one can be added without revisiting this. A keychain locked
# in this session shows no partition_id entry, which reads as "no". No early exit
# in the awk: closing the pipe would SIGPIPE security, and pipefail would turn
# that into "no".
key_allows_codesign() {
  security dump-keychain -a "$KEYCHAIN" 2>/dev/null | awk -v cn="$CN" '
    /^keychain: /                             { key = 0; named = 0 }
    /^class: 0x00000010/                      { key = 1 }
    index($0, "0x00000001 <blob>=\"" cn "\"") { named = 1 }
    /authorizations .*: partition_id/         { list = 1; next }
    list && /description: / {
      if (key && named) { seen = 1; if ($0 !~ / apple:(,|$)/) missing = 1 }
      list = 0
    }
    END { exit !(seen && !missing) }
  '
}

# The list takes the keychain's password, which security(1) reads from the terminal
# (its -k is deprecated), so someone has to be there to see the prompt: stderr
# counts, as a caller may leave stdin on a person's terminal with the prompt in
# its log. -l because without it the list of every signing key in the keychain is
# replaced. A wrong password exits 1 and changes nothing, so a run that finds the
# identity present still has to come through here.
allow_codesign() {
  if [[ ! -t 0 || ! -t 2 ]]; then
    echo "codesign cannot use the \"$CN\" key yet, and allowing it takes your login password: run this script in a terminal." >&2
    exit 1
  fi
  echo "macOS asks for your login password once, so that codesign can use the \"$CN\" key without a dialog."
  if ! security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$CN" "$KEYCHAIN" >/dev/null; then
    echo "codesign cannot use the \"$CN\" key yet: run this script again with your login password." >&2
    exit 1
  fi
}

# Idempotency: an untrusted self-signed cert does NOT appear in
# `find-identity -p codesigning` (that lists trusted identities only), so a
# naive guard there never trips and every re-run adds a duplicate — which
# then makes `codesign --sign "$CN"` ambiguous. Use `find-certificate` (lists
# untrusted too) and collapse any duplicates down to one.
hashes=$(security find-certificate -a -c "$CN" -Z "$KEYCHAIN" \
  2>/dev/null | awk '/SHA-1 hash:/ { print $3 }' || true)
hash_count=$(printf '%s\n' "$hashes" | grep -c . || true)

if [[ "$hash_count" -ge 1 ]]; then
  if [[ "$hash_count" -gt 1 ]]; then
    echo "found $hash_count duplicate \"$CN\" certs — collapsing to one"
    skip=true
    while IFS= read -r h; do
      [[ -z "$h" ]] && continue
      if $skip; then skip=false; continue; fi
      security delete-certificate -Z "$h" "$KEYCHAIN" >/dev/null 2>&1 || true
    done <<<"$hashes"
  fi
  echo "identity already present: $CN"
  key_allows_codesign || allow_codesign
  echo -n "$CN" > .signing-id
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $CN
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

# /usr/bin's, a LibreSSL every Mac has, never PATH's: an OpenSSL 3+ takes -legacy
# for these options and a LibreSSL refuses it, with this script's output hidden
# (macOS 26.5, LibreSSL 3.3.6, Tart VM, 2026-11-07).
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -config "$TMP/cert.cnf" >/dev/null 2>&1

# SHA-1 MAC / 3DES + a password: required for Apple's `security` to import the
# .p12 without "MAC verification failed". Weak crypto but irrelevant — the .p12
# lives in a per-run temp dir and is removed on exit.
P12PW="glance"
/usr/bin/openssl pkcs12 -export -macalg sha1 \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout "pass:$P12PW" -name "$CN" >/dev/null 2>&1

# -A opens the key's ACL to any app; codesign still needs allow_codesign.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$P12PW" -A >/dev/null
allow_codesign

echo -n "$CN" > .signing-id
echo "created identity: $CN"
# Self-signed + untrusted: it won't show under `find-identity -p codesigning`
# (that lists trusted identities only). codesign still uses it by name.
security find-certificate -c "$CN" -Z "$KEYCHAIN" 2>/dev/null \
  | grep 'SHA-1 hash' || true
echo "next: ./build.sh && ./install.sh"
