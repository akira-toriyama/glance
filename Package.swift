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
    targets: [
        .target(name: "GlanceCore"),
        .target(name: "GlanceAdapterMacOS", dependencies: ["GlanceCore"]),
        .executableTarget(
            name: "GlanceApp",
            dependencies: [
                "GlanceCore",
                "GlanceAdapterMacOS",
            ]),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore"]),
    ]
)
