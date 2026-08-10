import Foundation

/// glance's CLI arguments. Parsing is a pure function, so XCTest covers it.
public struct Args: Equatable {
    public var title: String
    public var atX: Double?
    public var atY: Double?
    public var markdown: Bool
    public var autoCloseSeconds: Double?
    public var width: Double?
    public var height: Double?
    public var copy: Bool
    /// Base body font size. nil = the adapter-side default (16pt).
    public var fontSize: Double?
    /// Highlightr theme name (a stock highlight.js theme). nil =
    /// `atom-one-dark` (the adapter-side hardcoded default).
    public var theme: String?
    /// No syntax highlighting at all (every code block is plain mono).
    /// Skips booting Highlightr, so it is the fastest.
    public var noHighlight: Bool
    /// Borderless HUD mode. Drops titleBar / closable / resizable for a
    /// rounded "notification-like" rectangle. For short toasts.
    public var hud: Bool
    /// The "clicking outside the panel does not close it" mode. The **X
    /// button** becomes the primary dismiss path; `--auto-close` is also
    /// disabled. Esc / ⌘W stay **as-is** so a mis-click can never wedge you
    /// (the keyboard safety valve). For long-lived references / notifications
    /// that must hold attention. Combining with `--hud` (no X button) or
    /// `--auto-close` (contradictory) errors in parseArgs.
    public var sticky: Bool

    public init(title: String = "",
                atX: Double? = nil,
                atY: Double? = nil,
                markdown: Bool = false,
                autoCloseSeconds: Double? = nil,
                width: Double? = nil,
                height: Double? = nil,
                copy: Bool = false,
                fontSize: Double? = nil,
                theme: String? = nil,
                noHighlight: Bool = false,
                hud: Bool = false,
                sticky: Bool = false) {
        self.title = title
        self.atX = atX
        self.atY = atY
        self.markdown = markdown
        self.autoCloseSeconds = autoCloseSeconds
        self.width = width
        self.height = height
        self.copy = copy
        self.fontSize = fontSize
        self.theme = theme
        self.noHighlight = noHighlight
        self.hud = hud
        self.sticky = sticky
    }
}

public enum ArgsParseError: Error, Equatable {
    case missingValue(String)
    case invalidNumber(String, String)
    case unknownFlag(String)
    case invalidCombination(String)
}

public enum ArgsAction {
    case showHelp
    case showVersion
    case viewer(Args)
}

public func parseArgs(_ argv: [String]) throws -> ArgsAction {
    var args = Args()
    var i = 0
    while i < argv.count {
        let a = argv[i]
        switch a {
        case "--help", "-h":
            return .showHelp
        case "--version", "-V":
            return .showVersion
        case "--title":
            guard i + 1 < argv.count else {
                throw ArgsParseError.missingValue(a)
            }
            args.title = argv[i + 1]
            i += 2
        case "--at":
            guard i + 2 < argv.count else {
                throw ArgsParseError.missingValue(a)
            }
            guard let x = Double(argv[i + 1]) else {
                throw ArgsParseError.invalidNumber(a, argv[i + 1])
            }
            guard let y = Double(argv[i + 2]) else {
                throw ArgsParseError.invalidNumber(a, argv[i + 2])
            }
            args.atX = x
            args.atY = y
            i += 3
        case "--markdown":
            args.markdown = true
            i += 1
        case "--copy":
            args.copy = true
            i += 1
        case "--auto-close":
            guard i + 1 < argv.count else {
                throw ArgsParseError.missingValue(a)
            }
            guard let n = Double(argv[i + 1]) else {
                throw ArgsParseError.invalidNumber(a, argv[i + 1])
            }
            args.autoCloseSeconds = n
            i += 2
        case "--width":
            guard i + 1 < argv.count else {
                throw ArgsParseError.missingValue(a)
            }
            guard let n = Double(argv[i + 1]) else {
                throw ArgsParseError.invalidNumber(a, argv[i + 1])
            }
            args.width = n
            i += 2
        case "--height":
            guard i + 1 < argv.count else {
                throw ArgsParseError.missingValue(a)
            }
            guard let n = Double(argv[i + 1]) else {
                throw ArgsParseError.invalidNumber(a, argv[i + 1])
            }
            args.height = n
            i += 2
        case "--font-size":
            guard i + 1 < argv.count else {
                throw ArgsParseError.missingValue(a)
            }
            guard let n = Double(argv[i + 1]) else {
                throw ArgsParseError.invalidNumber(a, argv[i + 1])
            }
            args.fontSize = n
            i += 2
        case "--theme":
            // Highlightr theme name: atom-one-dark / nord / monokai-sublime /
            // vs2015 / github-dark, …. An unknown name is a silent Highlightr
            // no-op (previous theme kept), so callers pass a correct name.
            guard i + 1 < argv.count else {
                throw ArgsParseError.missingValue(a)
            }
            args.theme = argv[i + 1]
            i += 2
        case "--no-highlight":
            args.noHighlight = true
            i += 1
        case "--hud":
            args.hud = true
            i += 1
        case "--sticky":
            args.sticky = true
            i += 1
        default:
            throw ArgsParseError.unknownFlag(a)
        }
    }
    if args.sticky && args.hud {
        throw ArgsParseError.invalidCombination(
            "--sticky requires the title bar close button; --hud is " +
            "borderless and has none")
    }
    if args.sticky && args.autoCloseSeconds != nil {
        throw ArgsParseError.invalidCombination(
            "--sticky and --auto-close are contradictory; drop one")
    }
    return .viewer(args)
}
