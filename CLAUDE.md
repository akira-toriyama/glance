# CLAUDE.md

このリポジトリで作業する Claude / エージェント向けの構造・制約・流儀。
人間の README は [README.md](README.md) / [README.ja.md](README.ja.md)。

## 用語

UI / 設定 / コード上の呼び名は [`docs/glossary.md`](docs/glossary.md) に従う
— 正規名（`ViewerPanel`, `non-activating panel`, `dismiss paths`,
`stdin pipeline`, `--auto-close`, `GLANCE_DEBUG`, `one-shot CLI`, …）のみを
使い、`Don't call it:` 側の同義語は使わない。用語の追加・改名はコード
変更と **同一 PR で** このファイルへ反映する。

## What this is

**glance** は stdin で受けた文字列を **非アクティブな macOS NSPanel** に表示する
one-shot CLI。pipeline の "結果表示端" として使う。

```
some-cmd | glance --title "Result" --at 800 500
```

設計の核は「**フォーカスを奪わない**」こと。`.nonactivatingPanel` style
mask + `becomesKeyOnlyIfNeeded` で、元のアプリでキー入力を続けながら
panel を眺められる UX（ツールバー風で、ソースアプリのフォーカスを保つ）。

連携想定:

```
トリガー（検知） → wand (menu でアクション選択) → shell action (curl/jq 等) → glance (表示)
```

## Architecture (SwiftPM 3-layer)

`facet` / `chord` / `perch` と同じヘキサゴナル分割:

```
Sources/
  GlanceCore/             pure logic: argv parser (Args / parseArgs / errors)。
                          Foundation のみ。AppKit を含まない。XCTest で
                          単体検証可能。
  GlanceAdapterMacOS/     ViewerPanel: NSPanel 生成 / NSTextView マウント /
                          NSEvent モニタ (click-outside, Esc) で dismiss。
                          AppKit はここだけ。
  GlanceApp/              @main: argv 解析 → stdin 読み → NSApp 起動 →
                          ViewerPanel.present。lifecycle.
Tests/GlanceCoreTests/    ArgsTests: flag parse + error cases。
```

## Build / Run

ビルドは SwiftPM (`swift build -c release`)。`build.sh` がラップして
`bin/glance` 配置 + codesign。

| script | 用途 |
|---|---|
| `./build.sh` | swift build → `bin/glance` cp → codesign (持続 / ad-hoc) |
| `./run.sh` (無印) / `--demo` | build + verbose demo 起動 (`GLANCE_DEBUG=1`; panel + stderr + `/tmp/glance.log`)。他アプリの `./run.sh`(launch) 相当 |
| `./run.sh --install` / `-i` | `install.sh` 委譲 (`~/.local/bin/glance` 配置・静音)。他アプリの brew install 相当 |
| `./stop.sh` | stuck panel が居たら `pkill`。通常は user dismiss で自滅 |
| `./install.sh` | build → `~/.local/bin/glance` 配置 |
| `./setup-signing-cert.sh` | 持続自己署名 identity (`glance-dev`) 作成 |
| `./scripts/build-icon.sh` | SF Symbol から `AppIcon.icns` 生成 (`text.viewfinder` / amber) |

production も `~/.local/bin/glance` 配置でよい (daemon ではないので
LaunchAgent 不要)。Homebrew は `akira-toriyama/tap/glance` を提供予定。

## Architecture (制約)

- **macOS 13+ (Ventura+)**。`.nonactivatingPanel` + `swift-markdown` / `Highlightr`
  レンダリングの動作前提。
- **one-shot CLI**。stdin 読み終わったら NSApp.run() → user dismiss →
  NSApp.terminate(nil) → プロセス終了。
- **focus を奪わない**: `.nonactivatingPanel` style mask、
  `becomesKeyOnlyIfNeeded`、`orderFrontRegardless()` で order front
  (makeKey はしない)。
- **dismiss 経路**: (1) panel 外クリック (global mouse monitor)、
  (2) Esc / ⌘W (panel が transient に key になった時の local key monitor)、
  (3) `--auto-close N` の N 秒タイマー、(4) 標準の panel close ボタン。
  `--sticky` は (1)(3) を無効化し X ボタン + Esc/⌘W を主役にする。
  `--hud` は borderless で (4) を持たない。
- **markdown rendering**: `swift-markdown` の AST を自前 visitor
  (`MarkdownRenderer` の `MarkupVisitor`) で `NSAttributedString` に変換
  (tables / task list / strikethrough 対応のため標準 API ではなく自前)。
  code block は `Highlightr` で syntax highlight (`--theme` / `--no-highlight`
  で制御)。色は sill role (`foreground` / `tertiary` / `primary` / `border`)
  に乗せてダークモード追従 (`labelColor` ではない)。
- **空 stdin は no-op**: pipeline 上流が空を吐いた時に空 panel を出さない
  (= 静かに exit 0)。
- **ネットワーク呼び出ししない**: HTTP 呼び出しは pipeline 上流の責務。
  glance は表示だけ。

### スコープ確定 (再提案しないこと)

- **複数表示**: 1 プロセス = 1 panel。多 panel UI は別ツール。
- **編集機能**: 表示のみ。stdin が source of truth、glance は read-only viewer。
- **インタラクション**: link click 程度は許容、それ以上の UI 操作は
  Raycast extension 等を使う方が筋。

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

`--sticky` は `--hud`（X ボタン無し）/ `--auto-close`（矛盾）と排他で、
指定すると `parseArgs` が `invalidCombination` を投げて exit 2。

**atelier Phase 3 (family CLI 文法統一): glance は OUT.** data-processing
(stdin→panel one-shot・domain 0 / verb 1) ゆえ yabai 式 domain-verb 文法の
対象外。横断 sub-規約には**既に適合済み**で追加の移行は不要:

- canonical-only — 短縮 alias は family carve-out の `-h` / `-V` のみ（他に
  bare-flag alias なし）。`--at <x> <y>` は既に空白区切り。
- unknown-flag は loud に `ArgsParseError.unknownFlag` → stderr ＋ **exit 2**
  （no silent fallback）。
- **死守の例外**: 空 stdin は **silent exit 0**（pipeline で上流が空を返した
  時に空 panel を出さない＝Unix filter 尾。`Main.swift` の guard）。

正典は [cli-grammar.md](https://github.com/akira-toriyama/atelier/blob/main/docs/cli-grammar.md)。

## Debugging

| ログ先 | 条件 |
|---|---|
| stderr | parse error / 起動失敗時、または `GLANCE_DEBUG=1` の debug ミラー |
| `/tmp/glance.log` | `GLANCE_DEBUG=1` 時の verbose trace (引数 / stdin サイズ / panel frame / dismiss) |
| (なし) | 通常運転中は黙る。"Result が出ない" → 上流 pipeline を疑う |

調査の早道:

- `printf 'x' | glance --title test` で最低限の表示確認 (`GLANCE_DEBUG=1`
  を前置すると trace 付き: `printf 'x' | GLANCE_DEBUG=1 glance --title test`)
- `./run.sh`(無印) / `--demo` は `GLANCE_DEBUG=1` 付きで起動 (stderr + /tmp/glance.log)
- 上流の問題なら `... | tee /tmp/glance-in.txt | glance ...` で
  入力を覗ける

**verbose の唯一のトリガは `GLANCE_DEBUG` 環境変数** (`--debug` flag は無い —
facet/chord/wand/perch 家系と統一)。通常 pipe 起動では set されず静か。
`Log` (always-on `Log.line` + gated `Log.debug`) は `GlanceCore` に在る。

## Conventions

- **コミット**: gitmoji + Conventional Commits。
  `scripts/hooks/commit-msg` がチェック。有効化:
  `git config core.hooksPath scripts/hooks`
- **PR**: タイトルも同じ形式 (`commit-lint.yml` がチェック)。
- **コメント**: WHY を書く。WHAT は識別子で語る。多段の docstring は禁止。
- **依存**: SwiftPM 経由で追加可。ライセンスは MIT / Apache-2 互換に
  限る。`Package.swift` への追加は PR description で根拠を書く
  (e.g. "swift-markdown: GFM tables / task lists / strikethrough のため")。
  build time と binary size への影響を意識する。

## CI (.github/workflows)

| ファイル | 役割 |
|---|---|
| `build.yml` | PR で macos runner 上 `./build.sh` + `swift test` + `--version` sanity |
| `shellcheck.yml` | shell スクリプトの lint |
| `commit-lint.yml` | commit / PR title が convention に従うか (reusable に委譲) |
| `glossary.yml` | `docs/glossary.md` から glossary SPA を生成し GitHub Pages へ deploy (PR は build のみ) |
| `taplo.yml` | `**/*.toml` の TOML lint (reusable に委譲) |
| `release.yml` | git-cliff (`cliff.toml`) でリリースノート生成 (rolling draft) |
| `update-tap.yml` | release publish 後に `akira-toriyama/homebrew-tap` を自動 bump |

`update-tap.yml` は `HOMEBREW_TAP_TOKEN` (fine-grained PAT) が必要。
未設定なら no-op で安全に skip。

## References (家風ソース)

glance の流儀は以下と意図的に揃えている (家風):

- [facet](https://github.com/akira-toriyama/facet) — workspace + window manager
- [chord](https://github.com/akira-toriyama/chord) — hotkey daemon
- [perch](https://github.com/akira-toriyama/perch) — keyboard-driven UI navigator
- [wand](https://github.com/akira-toriyama/wand) — gesture + launcher

共通: SwiftPM 3-layer / README EN/JA 並行 / `run.sh` `stop.sh` /
`scripts/build-icon.sh` / SF Symbol アイコン / `--help` `--version`
CLI / commit-msg hook / multi-workflow CI / Homebrew tap 外出し。

連携先 (glance 観点):

- トリガー（chord のホットキーやテキスト選択監視など） — 選択テキストを
  `$SELECTION` として pipeline に流す。
- [wand](https://github.com/akira-toriyama/wand) — `wand tome --open` で
  action 選択 UI を出す。クリックされた item の action-cmd が glance を
  呼ぶ pipeline 末端。

## Shared libraries (atelier)

このアプリは swift app family の共有ライブラリに乗る（plan [atelier](https://github.com/akira-toriyama/atelier)）。
共有 lib が持つ責務は**再実装せずライブラリ側を拡張**する（北極星＝「facet の theme を真似て」を二度と言わない）。
モジュール → target の正確な配線は [Package.swift](Package.swift) を正とする。

- **[sill](https://github.com/akira-toriyama/sill)** — 共有 theming 基盤。設計 → [`docs/DESIGN.md`](https://github.com/akira-toriyama/sill/blob/main/docs/DESIGN.md)。glance が使う: `Palette` / `PaletteKit`（theming のみ）。
- **[swift-toml-edit](https://github.com/akira-toriyama/swift-toml-edit)**（family 唯一の TOML 実装）は glance では**非使用**（glance は config.toml を持たない data-processing app）。

## Roadmap board (GitHub Projects)

issue 運用（集約 Project「roadmap」#5・Inbox 既定 / Status フロー / `Closes #N`）は
family 共通ポリシー。正典 → https://github.com/akira-toriyama/atelier/blob/main/docs/roadmap-board.md
