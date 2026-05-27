# Contributing to glance

Welcome — this is a small, focused project, so the bar is "your change
should still feel like *glance*". The points below help that.

> 日本語の説明が必要な場合は [README.ja.md](README.ja.md) を参照。

## What this is

`glance` is a one-shot macOS CLI that displays stdin in a
**non-activating** NSPanel. Two principles drive everything:

1. **Focus is sacred** — the panel never steals keyboard focus from
   the source app.
2. **glance is just the view** — no HTTP, no parsing, no transforms
   beyond rendering. The upstream pipeline (`curl | jq | ...`) does the
   real work; glance only shows the result.

If a feature would violate either, it probably belongs upstream or in a
different tool.

## Project layout

SwiftPM, hexagonal 3-layer (same as the [family](README.md#references)
of facet / chord / perch / eventfx):

```
Sources/
  GlanceCore/             pure logic (Args / parseArgs). Foundation only.
                          unit-testable without AppKit.
  GlanceAdapterMacOS/     AppKit. NSPanel, NSTextView, NSLayoutManager,
                          MarkdownRenderer, SyntaxHighlighter.
  GlanceApp/              @main. stdin read, NSApp lifecycle, --help.
Tests/
  GlanceCoreTests/        Args parsing.
  GlanceAdapterMacOSTests/ MarkdownRenderer AST → NSAttributedString
                          mapping contracts.
```

## Dev setup

```sh
git clone https://github.com/akira-toriyama/glance.git
cd glance

# Build
./build.sh                 # → bin/glance (codesigned)

# Run / install
./run.sh                   # build + install to ~/.local/bin
./run.sh --demo            # rich markdown smoke panel

# Tests — requires full Xcode (see below)
swift test
```

### Tests need full Xcode

`swift test` requires the **XCTest framework**, which ships with the
full Xcode bundle — **Command Line Tools alone is not enough**.

If `swift test` fails with `no such module 'XCTest'`:

1. Install Xcode from the App Store (or `xcode-select --install` is
   *not* enough by itself; you need the full IDE bundle for XCTest).
2. Point `xcode-select` at the Xcode `Developer` directory:

   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

3. Verify:

   ```sh
   xcrun --find xctest         # should print a path under Xcode.app
   swift test                  # should now run the suite
   ```

CI (`.github/workflows/build.yml`) uses the macOS runner which has
Xcode pre-installed, so PRs always get the full test pass even if you
skip locally.

### Commit message convention

[gitmoji](https://gitmoji.dev/) + [Conventional Commits](https://www.conventionalcommits.org/).

```
:emoji: type(scope): subject

  e.g.
  :sparkles: feat(viewer): add --hud borderless mode
  :bug: fix(args): reject negative font-size
  :memo: docs(readme): add screenshot section
```

Enable the pre-commit hook to catch malformed messages locally:

```sh
git config core.hooksPath scripts/hooks
```

PR titles must follow the same format — `commit-lint.yml` checks it.

## Pull requests

- Keep PRs focused — "one theme, one PR" is the norm here.
- Update `README.md` and `README.ja.md` together when CLI / behaviour
  changes (the two are intentionally kept in sync).
- Add tests when reasonable. Visual / panel behavior is hard to unit
  test — focus on the rendering / parsing contracts where assertions
  bite.
- CI must be green before merge (build / lint / shellcheck).

## Design constraints worth keeping

| Constraint | Why |
|---|---|
| **No network** | Pipeline upstream owns HTTP. `--copy` is the only side-effect glance allows itself. |
| **No Accessibility permission** | Avoid the "grant glance accessibility" friction. |
| **macOS 13+ only** | `.nonactivatingPanel` + `NSAttributedString(markdown:)` + `presentationIntent` lineage we lean on. |
| **Single panel per process** | One-shot. If you want multi-panel UX, build a different tool. |
| **No editing** | View only. stdin is source of truth. |

## Dependencies

Dependencies are allowed but kept tight:

- License must be **MIT / Apache-2 compatible**.
- Add via SwiftPM in `Package.swift`.
- The PR introducing a new dep should justify it in the body (what
  feature requires it, what was the alternative).
- Be mindful of build time / binary size — `Package.resolved` is
  committed for reproducibility.

Current deps:

- [swift-markdown](https://github.com/swiftlang/swift-markdown)
  (Apache-2) — CommonMark + GFM parser
- [Highlightr](https://github.com/raspu/Highlightr) (MIT) —
  highlight.js + JavaScriptCore wrapper for code syntax highlighting

## Release flow

- `release.yml` runs git-cliff on push to generate a **rolling draft
  release** with categorised notes.
- A human publishes the draft when ready.
- `update-tap.yml` then auto-bumps the
  [Homebrew tap](https://github.com/akira-toriyama/homebrew-tap)
  formula (needs `HOMEBREW_TAP_TOKEN` secret; no-op if missing).

## Reporting bugs

Open an issue with:

1. macOS version (`sw_vers`)
2. glance version (`glance --version`)
3. Exact stdin you piped in (or a minimal repro)
4. Expected vs actual behaviour
5. Screenshot if it's visual

For "panel does the wrong thing" issues, also include the `--markdown`
flag state — markdown rendering bugs and plain-text bugs have very
different causes.
