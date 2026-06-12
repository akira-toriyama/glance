import AppKit
import Foundation
import GlanceAdapterMacOS
import GlanceCore

/// `@main enum GlanceApp` — keeps `@testable import GlanceApp` working from
/// XCTest once CLI tests land. Same pattern facet / chord / perch.
@main
enum GlanceApp {
    static let version = "0.2.0"

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
        } catch let e as ArgsParseError {
            FileHandle.standardError.write(Data("glance: \(describe(e))\n".utf8))
            FileHandle.standardError.write(Data("glance: try --help\n".utf8))
            exit(2)
        } catch {
            FileHandle.standardError.write(Data("glance: \(error)\n".utf8))
            exit(2)
        }

        switch action {
        case .showHelp:    printHelp(); exit(0)
        case .showVersion: print("glance \(version)"); exit(0)
        case .viewer(let args):
            let text = readStdin()
            Log.debug("stdin: \(text.count) chars; markdown=\(args.markdown) "
                + "title=\(args.title.isEmpty ? "—" : args.title)")
            // 空 input は黙って no-op (pipeline で curl が失敗した時に
            // 空 panel が出てもノイズなだけ)。
            guard !text.isEmpty else {
                Log.debug("stdin empty — silent no-op exit")
                exit(0)
            }
            runViewer(text: text, args: args)
        }
    }

    /// AppKit を起動して NSPanel 表示 → user 操作で terminate。
    /// `setActivationPolicy(.accessory)` で Dock に出ないようにする。
    @MainActor
    static func runViewer(text: String, args: Args) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let viewer = ViewerPanel(text: text, args: args)
        viewer.present(autoCloseSeconds: args.autoCloseSeconds,
                       copy: args.copy,
                       copyText: text)
        Log.debug("panel presented — entering run loop")
        // viewer 内で dismiss されると NSApp.terminate が呼ばれてここから抜ける。
        app.run()
    }

    /// stdin から全部読む。pipe か redirect で text 流入を期待。
    static func readStdin() -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func describe(_ e: ArgsParseError) -> String {
        switch e {
        case .missingValue(let flag):
            return "\(flag) requires a value"
        case .invalidNumber(let flag, let raw):
            return "\(flag): not a number: \(raw)"
        case .unknownFlag(let f):
            return "unknown flag: \(f)"
        case .invalidCombination(let msg):
            return msg
        }
    }

    static func printHelp() {
        print("""
        glance \(version) — display stdin in a non-activating macOS popover

        glance reads stdin and shows it in a floating NSPanel. The panel does
        NOT take keyboard focus from the source app, so it's safe to use as
        the result-display end of a selection-driven pipeline.

        USAGE
          some-cmd | glance [flags]

        FLAGS
          --title <s>          window title
          --at <x> <y>         anchor (Cocoa screen coords, Y-up); panel top-
                               left at this point. Default: screen center.
          --markdown           render stdin as Markdown (NSAttributedString)
          --copy               also copy stdin to clipboard (pbcopy)
          --auto-close <s>     dismiss after N seconds
          --width <px>         panel width  (default 380)
          --height <px>        panel height (default: auto-size,
                               clamped 80–600pt)
          --font-size <pt>     body font size (default 16; markdown
                               headings scale relative to this)
          --theme <name>       Highlightr theme for code blocks (default
                               atom-one-dark). Try: nord, monokai-sublime,
                               vs2015, github-dark, etc.
          --no-highlight       skip syntax highlighting entirely (faster
                               start, no JSCore boot)
          --hud                borderless rounded-corner mode for short
                               toast-style display (no title bar)
          --sticky             only the title-bar X button dismisses the
                               panel (no click-outside, no auto-close).
                               Esc / ⌘W still work as a safety valve.
                               Mutually exclusive with --hud and
                               --auto-close.
          --version / -V       print version, exit
          --help / -h          print this help, exit

        EXIT CODES
          0   shown successfully (after dismissal)
          2   bad flag / parse error

        EXAMPLES
          printf 'Hello world' | glance --title 'Greeting'
          curl -s ... | jq -r .text | glance --title 'DeepL' --at 800 500
          claude-cli ... | glance --markdown --title 'Summary'

        See: https://github.com/akira-toriyama/glance
        """)
    }
}
