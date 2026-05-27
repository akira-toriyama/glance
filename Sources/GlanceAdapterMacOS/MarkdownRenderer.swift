import AppKit
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

    /// table header 用の薄い tint。vibrancy backdrop 上でセル区切りが見える
    /// 程度に控えめにする。
    fileprivate static let tableHeaderBackground = NSColor(name: nil) { app in
        let dark = app.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return dark
            ? NSColor(white: 1.0, alpha: 0.08)
            : NSColor(white: 0.0, alpha: 0.05)
    }

    /// table の外周罫線。内部の separatorColor だと vibrancy 上で輪郭が
    /// ぼやけるので、外側だけ少し濃く・太く独立指定。
    fileprivate static let tableOuterBorderColor = NSColor(name: nil) { app in
        let dark = app.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return dark
            ? NSColor(white: 1.0, alpha: 0.28)
            : NSColor(white: 0.0, alpha: 0.22)
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
        return inner
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        var code = codeBlock.code
        if code.hasSuffix("\n") { code.removeLast() }

        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.bodyLineSpacing
        p.firstLineHeadIndent = style.codeBlockIndent
        p.headIndent = style.codeBlockIndent
        p.paragraphSpacing = style.codeBlockParagraphSpacing
        p.paragraphSpacingBefore = style.codeBlockParagraphSpacing

        return NSAttributedString(string: code, attributes: [
            .font: monoFont,
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: style.codeBlockBackground,
            .paragraphStyle: p,
        ])
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
        let r = NSRange(location: 0, length: inner.length)
        // 全 paragraphStyle を indent 付きに差し替え (heading が入った場合も
        // 階層を保ったまま indent を上塗り)。
        inner.enumerateAttribute(.paragraphStyle, in: r) { value, range, _ in
            let p = (value as? NSParagraphStyle).flatMap {
                $0.mutableCopy() as? NSMutableParagraphStyle
            } ?? bodyParagraph()
            p.firstLineHeadIndent = style.blockquoteIndent
            p.headIndent = style.blockquoteIndent
            inner.addAttribute(.paragraphStyle, value: p, range: range)
        }
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
