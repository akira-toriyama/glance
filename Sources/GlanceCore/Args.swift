import Foundation

/// The `--at` point: the panel's top-left in Cocoa screen coordinates
/// (Y-up, across all screens). One value, not two optionals, so "x without
/// y" cannot exist past the parser. Either coordinate may be negative (a
/// screen left of / below the main one).
public struct Anchor: Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// glance's CLI arguments. Parsing is a pure function, so XCTest covers it.
/// `nil` on a sized option means "the adapter-side default" (width 380,
/// auto-sized height, 16pt body, the atom-one-dark code theme).
public struct Args: Equatable {
    public var title = ""
    public var at: Anchor?
    public var markdown = false
    /// Always > 0 when set — parseArgs rejects 0 and negatives.
    public var autoCloseSeconds: Double?
    /// Always > 0 when set.
    public var width: Double?
    /// Always > 0 when set.
    public var height: Double?
    public var copy = false
    /// Always > 0 when set.
    public var fontSize: Double?
    /// Highlightr theme name (a stock highlight.js theme).
    public var theme: String?
    /// No syntax highlighting at all (every code block is plain mono).
    /// Skips booting Highlightr, so it is the fastest.
    public var noHighlight = false
    /// Borderless HUD mode. Drops titleBar / closable / resizable for a
    /// rounded "notification-like" rectangle. For short toasts.
    public var hud = false
    /// The "clicking outside the panel does not close it" mode. The **X
    /// button** becomes the primary dismiss path; `--auto-close` is also
    /// disabled. Esc / ⌘W stay **as-is** so a mis-click can never wedge you
    /// (the keyboard safety valve). Combining with `--hud` (no X button) or
    /// `--auto-close` (contradictory) errors in parseArgs.
    public var sticky = false

    public init() {}
}

public enum ArgsParseError: Error, Equatable {
    case missingValue(String)
    case invalidNumber(String, String)
    /// A sized option (`--auto-close` / `--width` / `--height` /
    /// `--font-size`) given 0 or a negative. 0 seconds would dismiss the
    /// panel before it is seen and 0pt has no meaning, so both are loud
    /// (exit 2) like an unknown flag, never a silent "no timer".
    case nonPositive(String, String)
    case unknownFlag(String)
    case invalidCombination(String)

    /// The stderr line after `glance: `.
    public var message: String {
        switch self {
        case .missingValue(let flag):
            return "\(flag) requires a value"
        case .invalidNumber(let flag, let raw):
            return "\(flag): not a number: \(raw)"
        case .nonPositive(let flag, let raw):
            return "\(flag): must be greater than 0: \(raw)"
        case .unknownFlag(let flag):
            return "unknown flag: \(flag)"
        case .invalidCombination(let msg):
            return msg
        }
    }
}

public enum ArgsAction {
    case showHelp
    case showVersion
    case viewer(Args)
}

/// Walks argv; every `take…` consumes the value(s) after the flag at the
/// cursor and throws the flag's own error when they are missing or malformed.
private struct Cursor {
    let argv: [String]
    var index = 0

    var isAtEnd: Bool { index >= argv.count }

    mutating func next() -> String {
        defer { index += 1 }
        return argv[index]
    }

    mutating func takeValue(for flag: String) throws(ArgsParseError) -> String {
        guard !isAtEnd else { throw .missingValue(flag) }
        return next()
    }

    mutating func takeNumber(for flag: String) throws(ArgsParseError) -> Double {
        let raw = try takeValue(for: flag)
        guard let n = Double(raw) else { throw .invalidNumber(flag, raw) }
        return n
    }

    mutating func takePositive(for flag: String) throws(ArgsParseError) -> Double {
        let raw = try takeValue(for: flag)
        guard let n = Double(raw) else { throw .invalidNumber(flag, raw) }
        guard n > 0 else { throw .nonPositive(flag, raw) }
        return n
    }
}

public func parseArgs(_ argv: [String]) throws(ArgsParseError) -> ArgsAction {
    var args = Args()
    var cursor = Cursor(argv: argv)
    while !cursor.isAtEnd {
        let flag = cursor.next()
        switch flag {
        case "--help", "-h":
            return .showHelp
        case "--version", "-V":
            return .showVersion
        case "--title":
            args.title = try cursor.takeValue(for: flag)
        case "--at":
            // Both numbers must be present before either is parsed, so
            // `--at 100` reports the missing value, not "not a number".
            guard cursor.index + 1 < argv.count else { throw .missingValue(flag) }
            let x = try cursor.takeNumber(for: flag)
            let y = try cursor.takeNumber(for: flag)
            args.at = Anchor(x: x, y: y)
        case "--markdown":
            args.markdown = true
        case "--copy":
            args.copy = true
        case "--auto-close":
            args.autoCloseSeconds = try cursor.takePositive(for: flag)
        case "--width":
            args.width = try cursor.takePositive(for: flag)
        case "--height":
            args.height = try cursor.takePositive(for: flag)
        case "--font-size":
            args.fontSize = try cursor.takePositive(for: flag)
        case "--theme":
            // An unknown name is a silent Highlightr no-op (previous theme
            // kept), so the parser cannot validate it; callers pass a
            // correct name.
            args.theme = try cursor.takeValue(for: flag)
        case "--no-highlight":
            args.noHighlight = true
        case "--hud":
            args.hud = true
        case "--sticky":
            args.sticky = true
        default:
            throw .unknownFlag(flag)
        }
    }
    if args.sticky && args.hud {
        throw .invalidCombination(
            "--sticky requires the title bar close button; --hud is " +
            "borderless and has none")
    }
    if args.sticky && args.autoCloseSeconds != nil {
        throw .invalidCombination(
            "--sticky and --auto-close are contradictory; drop one")
    }
    return .viewer(args)
}
