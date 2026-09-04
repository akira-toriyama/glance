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
//   GlanceCore         pure logic: argv parsing, logging, the version
//                      constant. Foundation only.
//   GlanceAdapterMacOS NSPanel, NSTextView, event monitors, the markdown
//                      renderer. AppKit only.
//   GlanceApp          executable: @main, stdin read, app lifecycle.

import PackageDescription

let package = Package(
    name: "glance",
    // macOS 26 floor (t-tbar): sill's Palette / PaletteKit require macOS 26
    // since sill v2.0.0, so a .v13 consumer no longer links. The string form
    // is the only spelling both toolchains parse — CLT PackageDescription 6.1
    // has no .v26 case.
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "glance", targets: ["GlanceApp"]),
        .library(name: "GlanceCore", targets: ["GlanceCore"]),
    ],
    dependencies: [
        // swift-markdown (Apache-2): CommonMark + GFM (tables / task lists /
        // strikethrough) — covering what NSAttributedString(markdown:)
        // cannot reach. First-party Apple and lightweight.
        .package(url: "https://github.com/swiftlang/swift-markdown.git",
                 from: "0.4.0"),
        // Highlightr (MIT): a syntax highlighter running highlight.js on
        // JavaScriptCore. glance is likely to display code in many languages
        // (`claude -p` output etc.), so highlight.js's broad language support
        // beats the Swift-only Splash. JavaScriptCore ships with macOS, so
        // the added binary size is just the theme CSS + JS.
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
        //
        // `.upToNextMinor`, not `from:`: sill minors have moved API before
        // (6.0.0 made `paletteFor` failable), so a minor lands here as a
        // reviewed Dependabot PR that bumps this floor, never as a silent
        // resolve. glance's one theme reference is the typed
        // `Theme.catppuccinMocha`, so a catalog cut breaks the build rather
        // than repainting.
        .package(url: "https://github.com/akira-toriyama/sill", .upToNextMinor(from: "8.8.0")),
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
