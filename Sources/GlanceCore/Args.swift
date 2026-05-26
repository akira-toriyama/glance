import Foundation

/// glance の CLI 引数。parse は純粋関数なので XCTest で網羅可能。
public struct Args: Equatable {
    public var title: String
    public var atX: Double?
    public var atY: Double?
    public var markdown: Bool
    public var autoCloseSeconds: Double?
    public var width: Double?
    public var height: Double?
    public var copy: Bool

    public init(title: String = "",
                atX: Double? = nil,
                atY: Double? = nil,
                markdown: Bool = false,
                autoCloseSeconds: Double? = nil,
                width: Double? = nil,
                height: Double? = nil,
                copy: Bool = false) {
        self.title = title
        self.atX = atX
        self.atY = atY
        self.markdown = markdown
        self.autoCloseSeconds = autoCloseSeconds
        self.width = width
        self.height = height
        self.copy = copy
    }
}

public enum ArgsParseError: Error, Equatable {
    case missingValue(String)
    case invalidNumber(String, String)
    case unknownFlag(String)
}

public enum ArgsAction {
    case showHelp
    case showVersion
    case viewer(Args)
}

/// argv (CommandLine.arguments を drop した先頭以外) を解釈して
/// `ArgsAction` を返す。`--help` / `--version` は早期に分岐する。
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
            // 表示と同時に pbcopy するフラグ。翻訳結果を後で paste する
            // ようなフローで使う。表示は副作用ではなく主役なので、
            // panel を出した後に clipboard へ書き込む順。
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
        default:
            throw ArgsParseError.unknownFlag(a)
        }
    }
    return .viewer(args)
}
