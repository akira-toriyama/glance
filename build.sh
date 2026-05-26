#!/bin/sh
# Build glance via SwiftPM and place the release binary at bin/glance.
# Codesign at the end with the persistent self-signed identity if
# available; else ad-hoc. glance itself doesn't need AX, but family
# pattern keeps the signing flow consistent across repos.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

swift build -c release

mkdir -p bin
cp -f .build/release/glance bin/glance

identity=""
if [ -f .signing-id ]; then
  identity="$(cat .signing-id)"
fi
if [ -n "$identity" ] && \
   security find-certificate -c "$identity" \
     "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
  codesign --force --options runtime --sign "$identity" bin/glance
  echo "built: $DIR/bin/glance  (signed: $identity)"
else
  codesign --force --sign - bin/glance
  echo "built: $DIR/bin/glance  (signed: ad-hoc — run ./setup-signing-cert.sh for stable identity)"
fi
