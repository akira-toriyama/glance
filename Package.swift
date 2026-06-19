// swift-tools-version:6.0
//
// glance — display stdin in a native non-activating macOS popover (NSPanel).
//
// Pipe text in, glance pops a floating panel that does NOT steal focus from
// the source app. Used as the "result view" end of selection-driven
// pipelines (an upstream trigger → wand → action shell → glance).
//
// Architecture is hexagonal (Ports & Adapters), mirroring facet / chord /
// perch:
//
//   GlanceCore         pure logic: argv parsing, markdown detection,
//                      position math. Foundation only.
//   GlanceAdapterMacOS NSPanel, NSTextView, event monitors. AppKit only.
//   GlanceApp          executable: @main, stdin read, app lifecycle.

import PackageDescription

let package = Package(
    name: "glance",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "glance", targets: ["GlanceApp"]),
        .library(name: "GlanceCore", targets: ["GlanceCore"]),
    ],
    dependencies: [
        // swift-markdown (Apache-2): CommonMark + GFM (tables / task lists /
        // strikethrough)。NSAttributedString(markdown:) では届かない範囲を
        // カバーするため。Apple 純正で軽量。
        .package(url: "https://github.com/swiftlang/swift-markdown.git",
                 from: "0.4.0"),
        // Highlightr (MIT): highlight.js を JavaScriptCore で動かす syntax
        // highlighter。glance は claude-cli 出力等で多言語のコードを表示する
        // 可能性が高いので、Swift only な Splash より highlight.js の広い
        // 言語サポートを取る。JavaScriptCore は macOS 標準同梱なので追加
        // binary size はテーマ CSS + JS 程度。
        .package(url: "https://github.com/raspu/Highlightr.git",
                 from: "2.3.0"),
        // sill — the swift app family's shared theming library (plan
        // atelier). glance consumes `Palette` + `PaletteKit` (the AppKit
        // resolver): it resolves ONE fixed dark preset (catppuccin-mocha,
        // ≈ the old hand-tuned #1E1E1E) into the popover's panel chrome +
        // markdown role colours, so glance's look stays drift-free with the
        // rest of the family instead of hand-copied hex. No catalog
        // switching (glance is a transient result-view popover, not a
        // themed surface) and no Effects (no border / line-pets). The
        // Highlightr `--theme` code-syntax theme stays orthogonal +
        // untouched.
        //
        // Local dev: swap to `.package(path: "../sill")` for atomic
        // sill+glance editing; the committed form pins the published tag.
        .package(url: "https://github.com/akira-toriyama/sill", .upToNextMinor(from: "1.7.0")),
    ],
    targets: [
        .target(name: "GlanceCore"),
        .target(
            name: "GlanceAdapterMacOS",
            dependencies: [
                "GlanceCore",
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Highlightr", package: "Highlightr"),
                .product(name: "Palette", package: "sill"),
                .product(name: "PaletteKit", package: "sill"),
            ]),
        .executableTarget(
            name: "GlanceApp",
            dependencies: [
                "GlanceCore",
                "GlanceAdapterMacOS",
            ]),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore"]),
        .testTarget(
            name: "GlanceAdapterMacOSTests",
            dependencies: ["GlanceAdapterMacOS"]),
    ]
)
