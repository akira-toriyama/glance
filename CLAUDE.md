# CLAUDE.md

Structure, constraints, and house style for Claude / agents working in this
repository. The human README is [README.md](README.md) (English-only — the
fleet [doc-consistency-policy](https://github.com/akira-toriyama/.github/blob/main/docs/doc-consistency-policy.md)).

## Vocabulary

Names across UI / config / code follow [`docs/glossary.md`](docs/glossary.md)
— use only the canonical names (`ViewerPanel`, `non-activating panel`,
`dismiss paths`, `stdin pipeline`, `--auto-close`, `GLANCE_DEBUG`,
`one-shot CLI`, …), never the `Don't call it:` synonyms. Term additions and
renames land in this file **in the same PR** as the code change.

## What this is

**glance** is a one-shot CLI that shows the string received on stdin in a
**non-activating macOS NSPanel** — the "result display end" of a pipeline.

```
some-cmd | glance --title "Result" --at 800 500
```

The design core is "**never steal focus**". With the `.nonactivatingPanel`
style mask + `becomesKeyOnlyIfNeeded`, you keep typing in the original app
while looking at the panel (toolbar-like UX preserving the source app's
focus).

The intended chain:

```
trigger (detection) → wand (action choice via menu) → shell action (curl/jq …) → glance (display)
```

## Architecture (SwiftPM 3-layer)

The same hexagonal split as `facet` / `chord` / `perch`:

```
Sources/
  GlanceCore/             pure logic: the argv parser (Args / parseArgs /
                          errors), Log, GlanceVersion. Foundation only — no
                          AppKit. Unit-testable under XCTest.
  GlanceAdapterMacOS/     ViewerPanel: creates the NSPanel / mounts the
                          NSTextView / dismisses via NSEvent monitors
                          (click-outside, Esc). AppKit lives only here.
  GlanceApp/              @main: parse argv → read stdin → boot NSApp →
                          ViewerPanel.present. Lifecycle.
Tests/GlanceCoreTests/    ArgsTests: flag parsing + error cases.
```

## Build / Run

Builds are SwiftPM (`swift build -c release`). `build.sh` wraps it: places
`bin/glance` + codesigns.

| script | Purpose |
|---|---|
| `./build.sh` | swift build → cp to `bin/glance` → codesign (persistent / ad-hoc) |
| `./run.sh` (bare) / `--demo` | build + verbose demo (`GLANCE_DEBUG=1`; panel + stderr + `/tmp/glance.log`). The analogue of other apps' `./run.sh` (launch) |
| `./run.sh --install` / `-i` | delegates to `install.sh` (place into `~/.local/bin/glance`, quiet). The analogue of other apps' brew install |
| `./stop.sh` | `pkill` any stuck panel. Normally user dismiss self-terminates |
| `./install.sh` | build → place into `~/.local/bin/glance` |
| `./setup-signing-cert.sh` | create the persistent self-signed identity (`glance-dev`) |
| `./scripts/build-icon.sh` | generate `AppIcon.icns` from an SF Symbol (`text.viewfinder` / amber) |

Production placement is also `~/.local/bin/glance` (not a daemon, so no
LaunchAgent). Homebrew via `akira-toriyama/tap/glance` is planned.

## Architecture (constraints)

- **macOS 26+ (Tahoe+)** — because sill's `Palette` / `PaletteKit` carry a
  macOS 26 floor (t-tbar). `.nonactivatingPanel` + the `swift-markdown` /
  `Highlightr` rendering also run inside this floor.
- **One-shot CLI**: finish reading stdin → NSApp.run() → user dismiss →
  NSApp.terminate(nil) → process exit.
- **Never steal focus**: the `.nonactivatingPanel` style mask,
  `becomesKeyOnlyIfNeeded`, and `orderFrontRegardless()` to order front
  (never makeKey).
- **Dismiss paths**: (1) a click outside the panel (global mouse monitor),
  (2) Esc / ⌘W (a local key monitor while the panel is transiently key),
  (3) the `--auto-close N` timer, (4) the standard panel close button.
  `--sticky` disables (1)(3), promoting the X button + Esc/⌘W;
  `--hud` is borderless and lacks (4).
- **Markdown rendering**: a hand-rolled visitor (`MarkdownRenderer`'s
  `MarkupVisitor`) lowers the `swift-markdown` AST to `NSAttributedString`
  (hand-rolled rather than the stock API, for tables / task lists /
  strikethrough). Code blocks highlight via `Highlightr` (controlled by
  `--theme` / `--no-highlight`). Colors ride the sill roles (`foreground` /
  `tertiary` / `primary` / `border`) for dark-mode tracking (never
  `labelColor`).
- **Empty stdin is a no-op**: never show an empty panel when the pipeline
  upstream produced nothing (= quiet exit 0).
- **No network calls**: HTTP is the pipeline upstream's job; glance only
  displays.

### Settled scope (do not re-propose)

- **Multiple panels**: 1 process = 1 panel. A multi-panel UI is a different
  tool.
- **Editing**: display only. stdin is the source of truth; glance is a
  read-only viewer.
- **Interaction**: a link click is acceptable; anything beyond belongs in a
  Raycast extension or similar.

## CLI surface

```
some-cmd | glance              run viewer (read stdin, show panel)
                  --title <s>       window title
                  --at <x> <y>      Cocoa coords (Y-up), anchor at panel top-left
                  --markdown        render as Markdown (swift-markdown + Highlightr)
                  --copy            also pbcopy the input after showing the panel
                  --auto-close <s>  dismiss after N seconds
                  --width <px>      panel width  (default 380)
                  --height <px>     panel height (default: auto-size, 80–600)
                  --font-size <pt>  body font size (default 16; headings scale)
                  --theme <name>    Highlightr code theme (default atom-one-dark)
                  --no-highlight    skip syntax highlight (code = plain mono)
                  --hud             borderless HUD (no title bar / close button)
                  --sticky          strict: X/Esc only (no click-outside, no --auto-close)
glance --version / -V         print version, exit
glance --help / -h            print help, exit
```

`--sticky` is mutually exclusive with `--hud` (no X button) and
`--auto-close` (contradictory); combining makes `parseArgs` throw
`invalidCombination`, exit 2.

**atelier Phase 3 (the family CLI-grammar unification): glance is OUT.** As
data-processing (stdin→panel one-shot; 0 domains / 1 verb) it is outside
the yabai-style domain-verb grammar, and it **already conforms** to the
cross-cutting sub-conventions — no further migration:

- canonical-only — the only short aliases are the family carve-outs `-h` /
  `-V` (no other bare-flag aliases). `--at <x> <y>` is already
  space-separated.
- unknown flags are loud: `ArgsParseError.unknownFlag` → stderr + **exit 2**
  (no silent fallback).
- **The defended exception**: empty stdin is a **silent exit 0** (never an
  empty panel when the upstream returns nothing = the Unix filter tail;
  the guard in `Main.swift`).

Canon: [cli-grammar.md](https://github.com/akira-toriyama/atelier/blob/main/docs/cli-grammar.md).

## Debugging

| Log sink | Condition |
|---|---|
| stderr | parse errors / launch failures, or the `GLANCE_DEBUG=1` debug mirror |
| `/tmp/glance.log` | the verbose trace under `GLANCE_DEBUG=1` (args / stdin size / panel frame / dismiss) |
| (none) | silent in normal operation. "No result shows" → suspect the upstream pipeline |

Fast paths for investigation:

- `printf 'x' | glance --title test` for the minimal display check
  (prepend `GLANCE_DEBUG=1` for the trace:
  `printf 'x' | GLANCE_DEBUG=1 glance --title test`)
- `./run.sh` (bare) / `--demo` launch with `GLANCE_DEBUG=1` (stderr +
  /tmp/glance.log)
- For upstream problems, `... | tee /tmp/glance-in.txt | glance ...` lets
  you inspect the input

**The only verbose trigger is the `GLANCE_DEBUG` environment variable**
(there is no `--debug` flag — unified with the facet/chord/wand/perch
family). A normal pipe launch never sets it and stays quiet. `Log`
(always-on `Log.line` + gated `Log.debug`) lives in `GlanceCore`.

## Conventions

- **Commits**: gitmoji-driven — `<:gitmoji:>[(<scope>)][!] <subject>`. The
  leading `:code:` IS the type (the Conventional `<type>` word is retired;
  legacy `<type>(scope):` tokens are accept-and-ignored by the lint, so old
  history passes). The machine canon is `glyph rules`; install the local
  hook with `glyph hook install`
- **PRs**: titles use the same format (`commit-lint.yml` checks).
- **Comments**: write the WHY. The WHAT is told by identifiers. No stacked
  docstrings.
- **Dependencies**: additions via SwiftPM are fine; licenses limited to
  MIT / Apache-2 compatible. Justify `Package.swift` additions in the PR
  description (e.g. "swift-markdown: for GFM tables / task lists /
  strikethrough"). Mind build time and binary size.

## CI (.github/workflows)

| File | Role |
|---|---|
| `build.yml` | on PR: `./build.sh` + `swift test` + a `--version` sanity check on a macos runner |
| `shellcheck.yml` | lint the shell scripts |
| `commit-lint.yml` | commit / PR titles follow the convention (delegated to the reusable) |
| `glossary.yml` | build the glossary SPA from `docs/glossary.md` and deploy to GitHub Pages (PRs build only) |
| `taplo.yml` | TOML lint over `**/*.toml` (delegated to the reusable) |
| `release.yml` | delegates to glyph's reusable (binary mode) — semver/notes derived from gitmoji, rolling draft upserted. Its `version-sync` job fails when `GlanceVersion.current` (`Sources/GlanceCore/Version.swift`) ≠ the draft's tag: the PR that moves the verdict bumps the constant (glyph never rewrites source; the tap formula's `brew test` asserts `--version`) |
| `update-tap.yml` | auto-bump `akira-toriyama/homebrew-tap` after a release publishes |

`update-tap.yml` needs `HOMEBREW_TAP_DEPLOY_KEY` (the private half of the
tap's write deploy key; fleet-sync fans it out — t-6bhz). With neither it nor
the deprecated `HOMEBREW_TAP_TOKEN` set, the run fails loudly with the
remediation — there is no silent skip.

## References (house-style sources)

glance's style deliberately aligns with:

- [facet](https://github.com/akira-toriyama/facet) — workspace + window manager
- [chord](https://github.com/akira-toriyama/chord) — hotkey daemon
- [perch](https://github.com/akira-toriyama/perch) — keyboard-driven UI navigator
- [wand](https://github.com/akira-toriyama/wand) — gesture + launcher

Shared: the SwiftPM 3-layer split / English-only docs (the fleet
doc-consistency policy) / `run.sh` `stop.sh` / `scripts/build-icon.sh` /
SF Symbol icons / `--help` `--version` CLI / the commit-msg hook /
multi-workflow CI / the Homebrew tap kept out-of-repo.

Integration partners (from glance's viewpoint):

- The trigger (a chord hotkey, text-selection watching, …) — streams the
  selected text into the pipeline as `$SELECTION`.
- [wand](https://github.com/akira-toriyama/wand) — `wand tome --open` shows
  the action-choice UI; the clicked item's action-cmd calls glance at the
  pipeline's tail.

## Shared libraries (atelier)

This app rides the swift app family's shared libraries (plan:
[atelier](https://github.com/akira-toriyama/atelier)). A responsibility a
shared lib owns is **extended on the library side, never reimplemented**
(the north star: never again say "imitate facet's theme"). The exact
module → target wiring: [Package.swift](Package.swift) is the truth.

- **[sill](https://github.com/akira-toriyama/sill)** — the shared theming
  foundation; design →
  [`docs/DESIGN.md`](https://github.com/akira-toriyama/sill/blob/main/docs/DESIGN.md).
  glance uses: `Palette` / `PaletteKit` (theming only).
- **[swift-toml-edit](https://github.com/akira-toriyama/swift-toml-edit)**
  (the family's only TOML implementation) is **unused** in glance (a
  data-processing app with no config.toml).

## Roadmap board (GitHub Projects)

Issue operations (the aggregate Project "roadmap" #5, Inbox default /
Status flow / `Closes #N`) are family-wide policy. Canon →
https://github.com/akira-toriyama/atelier/blob/main/docs/roadmap-board.md
