// swift-tools-version:6.0
//
// glance — display stdin in a native non-activating macOS popover (NSPanel).
//
// Pipe text in, glance pops a floating panel that does NOT steal focus from
// the source app. Used as the "result view" end of selection-driven
// pipelines (eventfx → wand → action shell → glance).
//
// Architecture is hexagonal (Ports & Adapters), mirroring facet / chord /
// perch / eventfx:
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
    ],
    targets: [
        .target(name: "GlanceCore"),
        .target(
            name: "GlanceAdapterMacOS",
            dependencies: [
                "GlanceCore",
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Highlightr", package: "Highlightr"),
            ]),
        .executableTarget(
            name: "GlanceApp",
            dependencies: [
                "GlanceCore",
                "GlanceAdapterMacOS",
            ]),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore"]),
    ]
)
