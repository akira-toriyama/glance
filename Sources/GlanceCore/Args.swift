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
    /// 本文ベースフォントサイズ。nil なら adapter 側のデフォルト (16pt)。
    public var fontSize: Double?
    /// Highlightr のテーマ名 (highlight.js 標準テーマ)。nil なら
    /// `atom-one-dark` (adapter 側で hardcoded 既定)。
    public var theme: String?
    /// syntax highlight を一切しない (code block は全部 plain mono)。
    /// Highlightr 起動を skip するので最速。
    public var noHighlight: Bool
    /// borderless HUD モード。titleBar / closable / resizable を外し、
    /// 角丸付きの "通知っぽい" 矩形にする。短い toast 表示向け。
    public var hud: Bool

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
                hud: Bool = false) {
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
        case "--font-size":
            // 本文 pt サイズ。markdown 階層 (heading scales) は倍率なので
            // 同じ relative hierarchy を保ったまま全体が拡縮する。
            guard i + 1 < argv.count else {
                throw ArgsParseError.missingValue(a)
            }
            guard let n = Double(argv[i + 1]) else {
                throw ArgsParseError.invalidNumber(a, argv[i + 1])
            }
            args.fontSize = n
            i += 2
        case "--theme":
            // Highlightr テーマ名。 atom-one-dark / nord / monokai-sublime /
            // vs2015 / github-dark など。未知名は Highlightr が黙って no-op
            // (前テーマのまま) なので、使う側で正しい名前を渡す前提。
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
        default:
            throw ArgsParseError.unknownFlag(a)
        }
    }
    return .viewer(args)
}
