import AppKit
import Foundation
import GlanceAdapterMacOS
import GlanceCore

/// `@main enum`, not a top-level main.swift: an executable target with
/// top-level code cannot be `@testable import`ed. Same pattern as facet /
/// chord / perch.
@main
enum GlanceApp {
    @MainActor
    static func main() {
        let argv = Array(CommandLine.arguments.dropFirst())
        // Verbose logging is env-var-triggered (GLANCE_DEBUG=1) — run.sh's
        // --demo path sets it; a normal pipe invocation stays quiet. There is
        // no --debug flag (matches the facet/chord/wand/perch family).
        debugMode = ProcessInfo.processInfo.environment["GLANCE_DEBUG"] != nil
        let action: ArgsAction
        do {
            action = try parseArgs(argv)
        } catch {
            FileHandle.standardError.write(Data("glance: \(error.message)\n".utf8))
            FileHandle.standardError.write(Data("glance: try --help\n".utf8))
            exit(2)
        }

        switch action {
        case .showHelp:    print(HelpText.render(version: GlanceVersion.current)); exit(0)
        case .showVersion: print("glance \(GlanceVersion.current)"); exit(0)
        case .viewer(let args):
            let text = readStdin()
            Log.debug("stdin: \(text.count) chars; markdown=\(args.markdown) "
                + "title=\(args.title.isEmpty ? "—" : args.title)")
            // Empty input is a silent no-op (when curl fails in a
            // pipeline, an empty panel would just be noise).
            guard !text.isEmpty else {
                Log.debug("stdin empty — silent no-op exit")
                exit(0)
            }
            runViewer(text: text, args: args)
        }
    }

    /// Boot AppKit, show the NSPanel, terminate on user action.
    /// `setActivationPolicy(.accessory)` keeps it out of the Dock.
    @MainActor
    static func runViewer(text: String, args: Args) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let viewer = ViewerPanel(text: text, args: args)
        viewer.present(autoCloseSeconds: args.autoCloseSeconds,
                       copy: args.copy,
                       copyText: text)
        Log.debug("panel presented — entering run loop")
        // A dismiss inside the viewer calls NSApp.terminate, exiting here.
        app.run()
    }

    static func readStdin() -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

}
