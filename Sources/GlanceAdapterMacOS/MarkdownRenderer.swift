import AppKit
import Highlightr
import Markdown

/// swift-markdown の AST を AppKit の `NSAttributedString` に落とす renderer。
///
/// 以前は `NSAttributedString(markdown:)` を使っていたが、tables / task list /
/// strikethrough / footnote が描画されない制約があったため自前 visitor に
/// 置換。typography は `Style` で外から差し込めるので、ViewerPanel の constants
/// と同期させて使う。
public struct MarkdownRenderer {

    public struct Style {
        public var baseFontSize: CGFloat
        public var bodyLineSpacing: CGFloat
        public var inlineCodeBackground: NSColor
        public var codeBlockBackground: NSColor
        public var codeBlockIndent: CGFloat
        public var blockquoteIndent: CGFloat
        public var listIndent: CGFloat
        public var codeBlockParagraphSpacing: CGFloat
        /// heading レベル 1..6 のフォント倍率。h1 が大きく、h6 が body と同等。
        public var headingScales: [CGFloat]

        public init(baseFontSize: CGFloat,
                    bodyLineSpacing: CGFloat,
                    inlineCodeBackground: NSColor,
                    codeBlockBackground: NSColor,
                    codeBlockIndent: CGFloat,
                    blockquoteIndent: CGFloat,
                    listIndent: CGFloat = 18,
                    codeBlockParagraphSpacing: CGFloat,
                    headingScales: [CGFloat] = [1.75, 1.45, 1.25, 1.12, 1.05, 1.0]) {
            self.baseFontSize = baseFontSize
            self.bodyLineSpacing = bodyLineSpacing
            self.inlineCodeBackground = inlineCodeBackground
            self.codeBlockBackground = codeBlockBackground
            self.codeBlockIndent = codeBlockIndent
            self.blockquoteIndent = blockquoteIndent
            self.listIndent = listIndent
            self.codeBlockParagraphSpacing = codeBlockParagraphSpacing
            self.headingScales = headingScales
        }
    }

    public let style: Style

    public init(style: Style) {
        self.style = style
    }

    /// table header 用の bg。solid dark 前提で alpha 強め。
    fileprivate static let tableHeaderBackground =
        NSColor(white: 1.0, alpha: 0.15)

    /// table の外周罫線。内部の細い罫線とのコントラスト用に少し濃く。
    fileprivate static let tableOuterBorderColor =
        NSColor(white: 1.0, alpha: 0.28)

    /// blockquote 左バー (GitHub の ▎ 風)。dark bg #1E1E1E 上で識別できる
    /// 明るさ。あまり明るくすると主張しすぎるので #888 程度。
    fileprivate static let blockquoteBarColor =
        NSColor(white: 0.55, alpha: 1)

    /// Highlightr instance 共有用。デフォルトは atom-one-dark / highlight 有効。
    /// `--theme` / `--no-highlight` で書き換える時は ViewerPanel が `configure`
    /// を呼んで instance ごと差し替える (1 プロセス 1 panel なので race なし)。
    /// glance は単一スレッド UI なので nonisolated(unsafe) で安全。
    nonisolated(unsafe) fileprivate static var syntaxHighlighter = SyntaxHighlighter()

    /// CLI 引数を反映して highlighter を作り直す。`--no-highlight` 時は何も
    /// しない wrapper を入れる。
    public static func configureSyntaxHighlighter(theme: String?,
                                                  enabled: Bool) {
        if !enabled {
            syntaxHighlighter = SyntaxHighlighter(disabled: true)
            return
        }
        syntaxHighlighter = SyntaxHighlighter(
            theme: theme ?? "atom-one-dark")
    }

    public func render(_ text: String) -> NSAttributedString {
        let document = Document(parsing: text)
        var visitor = Visitor(style: style)
        let out = NSMutableAttributedString()
        let children = Array(document.children)
        for (index, child) in children.enumerated() {
            out.append(visitor.visit(child))
            // block 間は単一改行 + paragraphSpacing で視覚的余白を出す
            // (\n\n だと余白が二重になりがち)。最後の block には付けない。
            if index < children.count - 1 {
                out.append(NSAttributedString(string: "\n"))
            }
        }
        return out
    }
}

// MARK: - Visitor

private struct Visitor: MarkupVisitor {
    typealias Result = NSAttributedString

    let style: MarkdownRenderer.Style

    // MARK: font helpers

    private var bodyFont: NSFont {
        .systemFont(ofSize: style.baseFontSize)
    }

    private var monoFont: NSFont {
        .monospacedSystemFont(ofSize: style.baseFontSize, weight: .regular)
    }

    private func bodyParagraph() -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.bodyLineSpacing
        return p
    }

    private func bodyAttrs() -> [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: bodyParagraph(),
        ]
    }

    // MARK: default / unknown

    mutating func defaultVisit(_ markup: Markup) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for child in markup.children {
            out.append(visit(child))
        }
        return out
    }

    // MARK: inline

    mutating func visitText(_ text: Text) -> NSAttributedString {
        NSAttributedString(string: text.plainText, attributes: bodyAttrs())
    }

    mutating func visitSoftBreak(_ break_: SoftBreak) -> NSAttributedString {
        NSAttributedString(string: " ", attributes: bodyAttrs())
    }

    mutating func visitLineBreak(_ break_: LineBreak) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: bodyAttrs())
    }

    mutating func visitStrong(_ strong: Strong) -> NSAttributedString {
        let inner = NSMutableAttributedString()
        for child in strong.children { inner.append(visit(child)) }
        applyTrait(.boldFontMask, to: inner)
        return inner
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> NSAttributedString {
        let inner = NSMutableAttributedString()
        for child in emphasis.children { inner.append(visit(child)) }
        applyTrait(.italicFontMask, to: inner)
        return inner
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> NSAttributedString {
        let inner = NSMutableAttributedString()
        for child in strikethrough.children { inner.append(visit(child)) }
        let r = NSRange(location: 0, length: inner.length)
        inner.addAttribute(.strikethroughStyle,
                           value: NSUnderlineStyle.single.rawValue, range: r)
        return inner
    }

    mutating func visitInlineCode(_ code: InlineCode) -> NSAttributedString {
        NSAttributedString(string: code.code, attributes: [
            .font: monoFont,
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: style.inlineCodeBackground,
            .paragraphStyle: bodyParagraph(),
        ])
    }

    mutating func visitLink(_ link: Link) -> NSAttributedString {
        let inner = NSMutableAttributedString()
        for child in link.children { inner.append(visit(child)) }
        let r = NSRange(location: 0, length: inner.length)
        if let dest = link.destination, let url = URL(string: dest) {
            inner.addAttribute(.link, value: url, range: r)
        }
        inner.addAttribute(.foregroundColor,
                           value: NSColor.controlAccentColor, range: r)
        inner.addAttribute(.underlineStyle,
                           value: NSUnderlineStyle.single.rawValue, range: r)
        return inner
    }

    mutating func visitImage(_ image: Image) -> NSAttributedString {
        // 表示は描画しない (panel の中に画像 fetch までは入れない)。代替
        // テキストか URL を `[image: ...]` で表示。
        var alt = ""
        for child in image.children {
            if let text = child as? Text { alt += text.plainText }
        }
        let label = alt.isEmpty ? "image" : alt
        return NSAttributedString(string: "[image: \(label)]",
                                  attributes: bodyAttrs())
    }

    mutating func visitInlineHTML(_ inline: InlineHTML) -> NSAttributedString {
        // HTML はそのまま素のテキストで出す (HTML 解釈は scope 外)。
        NSAttributedString(string: inline.rawHTML, attributes: bodyAttrs())
    }

    // MARK: block

    mutating func visitParagraph(_ paragraph: Paragraph) -> NSAttributedString {
        let inner = NSMutableAttributedString()
        for child in paragraph.children { inner.append(visit(child)) }
        // 段落末の改行は呼び出し側 (Document / Blockquote / Listitem) が付ける。
        return inner
    }

    mutating func visitHeading(_ heading: Heading) -> NSAttributedString {
        let level = max(1, min(6, heading.level))
        let scaleIndex = level - 1
        let scale = scaleIndex < style.headingScales.count
            ? style.headingScales[scaleIndex] : 1.0
        let size = style.baseFontSize * scale
        let font = NSFont.boldSystemFont(ofSize: size)

        let inner = NSMutableAttributedString()
        for child in heading.children { inner.append(visit(child)) }

        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.bodyLineSpacing
        p.paragraphSpacingBefore = size * 0.4
        // heading 直後の本文との間に呼吸を入れる。0.25 だと詰まって見えるので
        // 0.45 で 1 行分弱の余白を作る。
        p.paragraphSpacing = size * 0.45

        let r = NSRange(location: 0, length: inner.length)
        inner.addAttributes([
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: p,
        ], range: r)
        // h1 / h2 は GitHub 風の下線を引く (.underlineStyle)。subtle な色で
        // セクション境界を強調する。h3+ は線を引くとうるさいので付けない。
        if level <= 2 {
            inner.addAttributes([
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: NSColor(white: 1.0, alpha: 0.18),
            ], range: r)
        }
        return inner
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        var code = codeBlock.code
        if code.hasSuffix("\n") { code.removeLast() }

        // 背景は 1 セルだけの NSTextTable で囲って段落矩形を描く。
        //   - `.backgroundColor` attr → 文字の後ろにしか描かれず、行間 gap で
        //      "行ごとの pill" に千切れる
        //   - 裸の NSTextBlock → width 未設定で 1 文字幅に折りたたまれる
        // GFM table で動いている仕組みをそのまま流用する。
        let table = NSTextTable()
        table.numberOfColumns = 1
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.hidesEmptyCells = false

        let block = NSTextTableBlock(
            table: table,
            startingRow: 0, rowSpan: 1,
            startingColumn: 0, columnSpan: 1)
        block.backgroundColor = style.codeBlockBackground
        block.setWidth(12, type: .absoluteValueType, for: .padding)
        block.setWidth(0,  type: .absoluteValueType, for: .border)
        // 本文との対比で "ブロック" 感を出す左右の外側 margin。上下は
        // paragraphSpacing が担うのでここは horizontal のみ。
        block.setWidth(6, type: .absoluteValueType, for: .margin, edge: .minX)
        block.setWidth(6, type: .absoluteValueType, for: .margin, edge: .maxX)

        // code paragraph style (本体)。
        let codeP = NSMutableParagraphStyle()
        // コードは body より行間を詰めた方がコードっぽく密に見える。
        codeP.lineSpacing = 2
        // 長い 1 行は word ではなく char 単位で wrap (code に word 境界の
        // 概念が薄いので半端な空白で折り返さない)。
        codeP.lineBreakMode = .byCharWrapping
        codeP.textBlocks = [block]
        codeP.paragraphSpacing = style.codeBlockParagraphSpacing
        codeP.paragraphSpacingBefore = style.codeBlockParagraphSpacing

        let result = NSMutableAttributedString()

        // (B) 言語ラベル: cell 内最初の段落として右寄せの dim text で言語名を
        // 表示 (VSCode の "右上 chip" の代替。同じ textBlock なので背景は
        // 連続したまま)。
        if let lang = codeBlock.language?.trimmingCharacters(in: .whitespaces),
           !lang.isEmpty {
            let labelP = NSMutableParagraphStyle()
            labelP.alignment = .right
            labelP.lineSpacing = 0
            labelP.textBlocks = [block]
            // code 本体の paragraphSpacingBefore が cell 内の縦余白を作るので
            // label 側では追加しない。
            let labelFont = NSFont.monospacedSystemFont(
                ofSize: style.baseFontSize * 0.78, weight: .regular)
            let labelAttr = NSAttributedString(string: lang + "\n",
                                               attributes: [
                .font: labelFont,
                .foregroundColor: NSColor(white: 0.50, alpha: 1),
                .paragraphStyle: labelP,
            ])
            result.append(labelAttr)
        }

        // Highlightr で syntax highlight。fence 言語指定 (```swift 等) があれば
        // それを使い、無ければ auto-detect。highlighter が落ちた / 言語が未知の
        // 場合は plain mono に fallback。
        let highlighted = MarkdownRenderer.syntaxHighlighter
            .highlight(code, language: codeBlock.language)

        let codeAttr: NSMutableAttributedString
        if let hl = highlighted {
            codeAttr = NSMutableAttributedString(attributedString: hl)
            let cr = NSRange(location: 0, length: codeAttr.length)
            // Highlightr が付けた `.backgroundColor` (theme の bg) は textBlock
            // の bg と二重になって汚いので消す。
            codeAttr.removeAttribute(.backgroundColor, range: cr)
            // font を SF Mono / baseFontSize に統一しつつ bold / italic 等の
            // trait は維持。
            codeAttr.enumerateAttribute(.font, in: cr) { value, range, _ in
                let original = (value as? NSFont) ?? monoFont
                let traits = original.fontDescriptor.symbolicTraits
                let base = monoFont.fontDescriptor.withSymbolicTraits(traits)
                let font = NSFont(descriptor: base, size: style.baseFontSize)
                    ?? monoFont
                codeAttr.addAttribute(.font, value: font, range: range)
            }
        } else {
            codeAttr = NSMutableAttributedString(string: code, attributes: [
                .font: monoFont,
                .foregroundColor: NSColor.labelColor,
            ])
        }
        // セル末は \n でパラグラフ終端 (textBlock の境界)。これが無いと
        // 後続 block と同じパラグラフになり、cell が閉じない。
        codeAttr.append(NSAttributedString(string: "\n"))
        let codeRange = NSRange(location: 0, length: codeAttr.length)
        codeAttr.addAttribute(.paragraphStyle, value: codeP, range: codeRange)

        result.append(codeAttr)
        return result
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> NSAttributedString {
        // raw HTML はそのまま monospace で。HTML レンダリングは scope 外。
        let p = bodyParagraph()
        return NSAttributedString(string: html.rawHTML, attributes: [
            .font: monoFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: p,
        ])
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> NSAttributedString {
        let inner = NSMutableAttributedString()
        let children = Array(blockQuote.children)
        for (index, child) in children.enumerated() {
            inner.append(visit(child))
            if index < children.count - 1 {
                inner.append(NSAttributedString(string: "\n", attributes: bodyAttrs()))
            }
        }

        // GitHub 風の左バー: 1-cell NSTextTable で左 border だけ太く色付き、
        // 他 edge は border 0。NSTextBlock 単体だと layout が崩れるので table
        // で囲うのが安定。collapsesBorders=true だと 1-cell 時に border が
        // 省略されることがあるので false にして確実に描く。
        let table = NSTextTable()
        table.numberOfColumns = 1
        table.collapsesBorders = false
        table.hidesEmptyCells = false

        let block = NSTextTableBlock(
            table: table,
            startingRow: 0, rowSpan: 1,
            startingColumn: 0, columnSpan: 1)
        block.setWidth(0, type: .absoluteValueType, for: .border)
        block.setWidth(4, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(MarkdownRenderer.blockquoteBarColor, for: .minX)
        // 左バーと本文の隙間 + 上下に呼吸。
        block.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(4,  type: .absoluteValueType, for: .padding, edge: .maxX)
        block.setWidth(2,  type: .absoluteValueType, for: .padding, edge: .minY)
        block.setWidth(2,  type: .absoluteValueType, for: .padding, edge: .maxY)

        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.bodyLineSpacing
        p.textBlocks = [block]

        // セル末は \n でパラグラフ終端 (cell が閉じる)。
        inner.append(NSAttributedString(string: "\n"))
        let r = NSRange(location: 0, length: inner.length)
        inner.addAttribute(.paragraphStyle, value: p, range: r)
        inner.addAttribute(.foregroundColor,
                           value: NSColor.secondaryLabelColor, range: r)
        return inner
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let items = list.children.compactMap { $0 as? ListItem }
        for (index, item) in items.enumerated() {
            let prefix = listItemPrefix(item) ?? "•  "
            out.append(renderListItem(item, prefix: prefix))
            if index < items.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: bodyAttrs()))
            }
        }
        return out
    }

    mutating func visitOrderedList(_ list: OrderedList) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let items = list.children.compactMap { $0 as? ListItem }
        let start = Int(list.startIndex)
        for (index, item) in items.enumerated() {
            let prefix = "\(start + index).  "
            out.append(renderListItem(item, prefix: prefix))
            if index < items.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: bodyAttrs()))
            }
        }
        return out
    }

    private mutating func listItemPrefix(_ item: ListItem) -> String? {
        // GFM の task list は ListItem.checkbox に値が入る。
        switch item.checkbox {
        case .checked:   return "☑  "
        case .unchecked: return "☐  "
        case .none:      return nil
        }
    }

    private mutating func renderListItem(_ item: ListItem,
                                         prefix: String) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.bodyLineSpacing
        p.firstLineHeadIndent = 0
        p.headIndent = style.listIndent

        let out = NSMutableAttributedString(string: prefix, attributes: [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: p,
        ])
        let children = Array(item.children)
        for (index, child) in children.enumerated() {
            out.append(visit(child))
            if index < children.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: bodyAttrs()))
            }
        }
        // ListItem 内の全 paragraphStyle に headIndent を適用 (nest 対応)。
        let r = NSRange(location: 0, length: out.length)
        out.enumerateAttribute(.paragraphStyle, in: r) { value, range, _ in
            let ps = (value as? NSParagraphStyle).flatMap {
                $0.mutableCopy() as? NSMutableParagraphStyle
            } ?? bodyParagraph()
            // 既存 indent との合成: 1 段目だけ prefix 分の indent をゼロに
            // しておく (`p.firstLineHeadIndent = 0`)。それ以外は同じ headIndent。
            if range.location == 0 {
                ps.firstLineHeadIndent = 0
            } else {
                ps.firstLineHeadIndent = style.listIndent
            }
            ps.headIndent = style.listIndent
            out.addAttribute(.paragraphStyle, value: ps, range: range)
        }
        return out
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> NSAttributedString {
        // NSTextView での hr は AppKit 標準 attribute では出しにくいので
        // U+2500 BOX DRAWINGS LIGHT HORIZONTAL を画面幅っぽく敷く。
        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.bodyLineSpacing
        p.paragraphSpacing = style.bodyLineSpacing * 2
        p.paragraphSpacingBefore = style.bodyLineSpacing * 2
        return NSAttributedString(
            string: String(repeating: "─", count: 40),
            attributes: [
                .font: bodyFont,
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: p,
            ])
    }

    // MARK: table

    /// GFM table を NSTextTable + NSTextTableBlock で "本物の罫線" に。
    /// mono-space 擬似罫線だと CJK の wide 幅で列が崩れるのを根本回避。
    /// header 行は薄い背景 + bold、各セルは細い罫線 + padding で sticky な
    /// 見た目になる。
    mutating func visitTable(_ table: Table) -> NSAttributedString {
        let head = Array(table.head.cells)
        let bodyRows: [[Markdown.Table.Cell]] = table.body.rows.map {
            Array($0.cells)
        }
        let columns = max(head.count, bodyRows.map { $0.count }.max() ?? 0)
        guard columns > 0 else { return NSAttributedString() }

        let textTable = NSTextTable()
        textTable.numberOfColumns = columns
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false
        // 外周だけ濃く太く: collapsesBorders=true なので隣接 border は太い方が
        // 勝つ。cell 側は 0.5pt subtle、table 側は 1.2pt はっきり → 結果として
        // 外周だけ濃い枠が出る。
        textTable.setBorderColor(MarkdownRenderer.tableOuterBorderColor)
        textTable.setWidth(1.2, type: .absoluteValueType, for: .border)

        let out = NSMutableAttributedString()
        // header
        out.append(renderTableRow(head, columns: columns,
                                  rowIndex: 0, isHeader: true,
                                  table: textTable))
        // body
        for (rowOffset, row) in bodyRows.enumerated() {
            out.append(renderTableRow(row, columns: columns,
                                      rowIndex: rowOffset + 1,
                                      isHeader: false,
                                      table: textTable))
        }
        return out
    }

    private mutating func renderTableRow(_ cells: [Markdown.Table.Cell],
                                         columns: Int,
                                         rowIndex: Int,
                                         isHeader: Bool,
                                         table textTable: NSTextTable) -> NSAttributedString {
        let row = NSMutableAttributedString()
        for colIndex in 0..<columns {
            let block = makeTableCellBlock(table: textTable,
                                           row: rowIndex,
                                           column: colIndex,
                                           isHeader: isHeader)
            let p = NSMutableParagraphStyle()
            p.textBlocks = [block]
            p.lineSpacing = style.bodyLineSpacing

            let inner = NSMutableAttributedString()
            if colIndex < cells.count {
                for child in cells[colIndex].children { inner.append(visit(child)) }
            }
            if isHeader {
                applyTrait(.boldFontMask, to: inner)
            }
            // セル末は改行 = paragraph 終端 (textBlock の境界)。
            inner.append(NSAttributedString(string: "\n"))
            let r = NSRange(location: 0, length: inner.length)
            inner.addAttribute(.paragraphStyle, value: p, range: r)
            // 既存 font が無い run (空セル) のために font を敷いておく。
            inner.enumerateAttribute(.font, in: r) { value, range, _ in
                if value == nil {
                    inner.addAttribute(.font, value: bodyFont, range: range)
                }
            }
            row.append(inner)
        }
        return row
    }

    private func makeTableCellBlock(table: NSTextTable,
                                    row: Int,
                                    column: Int,
                                    isHeader: Bool) -> NSTextTableBlock {
        let block = NSTextTableBlock(table: table,
                                     startingRow: row, rowSpan: 1,
                                     startingColumn: column, columnSpan: 1)
        block.setBorderColor(NSColor.separatorColor)
        block.setWidth(0.5, type: .absoluteValueType, for: .border)
        block.setWidth(8,   type: .absoluteValueType, for: .padding)
        if isHeader {
            block.backgroundColor = MarkdownRenderer.tableHeaderBackground
        }
        return block
    }

    // MARK: helpers

    private func applyTrait(_ trait: NSFontTraitMask, to s: NSMutableAttributedString) {
        let r = NSRange(location: 0, length: s.length)
        s.enumerateAttribute(.font, in: r) { value, range, _ in
            let original = (value as? NSFont) ?? bodyFont
            let traited = NSFontManager.shared.convert(original, toHaveTrait: trait)
            s.addAttribute(.font, value: traited, range: range)
        }
    }
}

// MARK: - SyntaxHighlighter

/// Highlightr (highlight.js + JavaScriptCore) を 1 instance だけ抱える
/// 薄い wrapper。theme は CLI から差し替え可能 (`--theme`)、`--no-highlight`
/// 時は disabled モードで常に nil を返す (Highlightr 起動も skip)。
/// MarkupVisitor の要件が非 isolated なので、これも非 isolated にしておく。
final class SyntaxHighlighter {
    private let highlightr: Highlightr?
    private let disabled: Bool

    init(theme: String = "atom-one-dark", disabled: Bool = false) {
        self.disabled = disabled
        if disabled {
            self.highlightr = nil
        } else {
            self.highlightr = Highlightr()
            _ = highlightr?.setTheme(to: theme)
        }
    }

    /// 言語 hint があれば指定で highlight。無ければ何もせず nil (auto-detect
    /// は意図しない highlight を生むので切る)。disabled 時も常に nil。caller
    /// は nil 時 plain mono に fallback する。
    func highlight(_ code: String, language: String?) -> NSAttributedString? {
        guard !disabled else { return nil }
        let lang = (language ?? "").trimmingCharacters(in: .whitespaces)
        guard !lang.isEmpty else { return nil }
        return highlightr?.highlight(code, as: lang.lowercased(),
                                     fastRender: true)
    }
}
