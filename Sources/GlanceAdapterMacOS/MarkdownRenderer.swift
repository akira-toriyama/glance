import AppKit
import Highlightr
import Markdown

/// The renderer lowering a swift-markdown AST into an AppKit
/// `NSAttributedString`.
///
/// It used `NSAttributedString(markdown:)` before, but tables / task lists /
/// strikethrough / footnotes never rendered under that constraint, so a
/// hand-rolled visitor replaced it. Typography and colors come in through
/// `Style`; the renderer owns no constants of its own.
public struct MarkdownRenderer {

    public struct Style {
        public var baseFontSize: CGFloat
        public var bodyLineSpacing: CGFloat
        /// Foreground for body / headings / lists / code-body fallback (sill `foreground`).
        public var foreground: NSColor
        /// De-emphasized text: blockquotes / raw-HTML bodies / code-block
        /// language labels / horizontal rules (sill `tertiary` =
        /// foreground@0.55). mocha's `muted` (#6C7086) misses AA on #1E1E2E
        /// (3.36:1), so the readable foreground-derived tertiary (~6.69:1)
        /// is used instead.
        public var tertiary: NSColor
        /// Link color (sill `primary`).
        public var primary: NSColor
        /// Thin inner table-cell rules (sill `border`).
        public var border: NSColor
        /// Inline-code pill background (sill `ink(.wash, of:.foreground)`).
        public var inlineCodeBackground: NSColor
        /// Code-block background (sill `ink(.subtle, of:.foreground)`).
        public var codeBlockBackground: NSColor
        /// Faint table-header-row background (sill `ink(.subtle, of:.foreground)`).
        public var tableHeaderBackground: NSColor
        /// Dark outer table border (sill `ink(.wash, of:.foreground)`).
        public var tableOuterBorder: NSColor
        /// Blockquote left bar, GitHub's ▎ style (sill `ink(.strong, of:.foreground)`).
        public var blockquoteBar: NSColor
        /// The subtle h1 / h2 underline color (sill `ink(.subtle, of:.foreground)`).
        public var headingUnderline: NSColor
        public var codeBlockIndent: CGFloat
        public var blockquoteIndent: CGFloat
        public var listIndent: CGFloat
        public var codeBlockParagraphSpacing: CGFloat
        /// Font multipliers for heading levels 1..6. h1 large, h6 equal to body.
        public var headingScales: [CGFloat]

        public init(baseFontSize: CGFloat,
                    bodyLineSpacing: CGFloat,
                    foreground: NSColor,
                    tertiary: NSColor,
                    primary: NSColor,
                    border: NSColor,
                    inlineCodeBackground: NSColor,
                    codeBlockBackground: NSColor,
                    tableHeaderBackground: NSColor,
                    tableOuterBorder: NSColor,
                    blockquoteBar: NSColor,
                    headingUnderline: NSColor,
                    codeBlockIndent: CGFloat,
                    blockquoteIndent: CGFloat,
                    listIndent: CGFloat = 18,
                    codeBlockParagraphSpacing: CGFloat,
                    headingScales: [CGFloat] = [1.75, 1.45, 1.25, 1.12, 1.05, 1.0]) {
            self.baseFontSize = baseFontSize
            self.bodyLineSpacing = bodyLineSpacing
            self.foreground = foreground
            self.tertiary = tertiary
            self.primary = primary
            self.border = border
            self.inlineCodeBackground = inlineCodeBackground
            self.codeBlockBackground = codeBlockBackground
            self.tableHeaderBackground = tableHeaderBackground
            self.tableOuterBorder = tableOuterBorder
            self.blockquoteBar = blockquoteBar
            self.headingUnderline = headingUnderline
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

    /// The shared Highlightr instance. ViewerPanel swaps the whole instance
    /// via `configure` before the first render (`--theme` /
    /// `--no-highlight`); one process shows one panel, so no write follows,
    /// and nonisolated(unsafe) rides on the single UI thread.
    nonisolated(unsafe) fileprivate static var syntaxHighlighter = SyntaxHighlighter()

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
            // Between blocks: a single newline + paragraphSpacing provides
            // the visual gap (\n\n tends to double it). None after the last
            // block.
            if index < children.count - 1 {
                out.append(NSAttributedString(string: "\n"))
            }
        }
        return out
    }
}

private struct Visitor: MarkupVisitor {
    typealias Result = NSAttributedString

    let style: MarkdownRenderer.Style

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
            .foregroundColor: style.foreground,
            .paragraphStyle: bodyParagraph(),
        ]
    }

    mutating func defaultVisit(_ markup: Markup) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for child in markup.children {
            out.append(visit(child))
        }
        return out
    }

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
            .foregroundColor: style.foreground,
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
                           value: style.primary, range: r)
        inner.addAttribute(.underlineStyle,
                           value: NSUnderlineStyle.single.rawValue, range: r)
        return inner
    }

    mutating func visitImage(_ image: Image) -> NSAttributedString {
        // Not rendered (no image fetching inside the panel). Shows the alt
        // text or URL as `[image: ...]`.
        var alt = ""
        for child in image.children {
            if let text = child as? Text { alt += text.plainText }
        }
        let label = alt.isEmpty ? "image" : alt
        return NSAttributedString(string: "[image: \(label)]",
                                  attributes: bodyAttrs())
    }

    mutating func visitInlineHTML(_ inline: InlineHTML) -> NSAttributedString {
        // HTML is emitted as plain text (HTML interpretation is out of scope).
        NSAttributedString(string: inline.rawHTML, attributes: bodyAttrs())
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> NSAttributedString {
        let inner = NSMutableAttributedString()
        for child in paragraph.children { inner.append(visit(child)) }
        // The paragraph-final newline is the caller's job (Document / Blockquote / Listitem).
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
        // Breathing room between a heading and the body after it. 0.25 looks
        // cramped; 0.45 gives just under a line.
        p.paragraphSpacing = size * 0.45

        let r = NSRange(location: 0, length: inner.length)
        inner.addAttributes([
            .font: font,
            .foregroundColor: style.foreground,
            .paragraphStyle: p,
        ], range: r)
        // h1 / h2 get a GitHub-style underline (.underlineStyle), a subtle
        // color emphasizing the section boundary. h3+ would be noisy — none.
        if level <= 2 {
            inner.addAttributes([
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: style.headingUnderline,
            ], range: r)
        }
        return inner
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        var code = codeBlock.code
        if code.hasSuffix("\n") { code.removeLast() }

        // The background wraps in a 1-cell NSTextTable to paint a paragraph
        // rectangle:
        //   - a `.backgroundColor` attr only paints behind glyphs, tearing
        //     into "per-line pills" at line gaps
        //   - a bare NSTextBlock collapses to one character width with no
        //     width set
        // Reuses the machinery already working for GFM tables.
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
        // Outer horizontal margins giving the "block" contrast against the
        // body. Vertical is paragraphSpacing's job — horizontal only here.
        block.setWidth(6, type: .absoluteValueType, for: .margin, edge: .minX)
        block.setWidth(6, type: .absoluteValueType, for: .margin, edge: .maxX)

        let codeP = NSMutableParagraphStyle()
        // Tighter line spacing than body reads denser, more code-like.
        codeP.lineSpacing = 2
        // Long lines wrap per character, not per word (code has little
        // notion of word boundaries — don't break at stray spaces).
        codeP.lineBreakMode = .byCharWrapping
        codeP.textBlocks = [block]
        codeP.paragraphSpacing = style.codeBlockParagraphSpacing
        codeP.paragraphSpacingBefore = style.codeBlockParagraphSpacing

        let result = NSMutableAttributedString()

        // The language label: the cell's first paragraph, right-aligned dim
        // text naming the language (the stand-in for VSCode's top-right
        // chip; same textBlock, so the background stays continuous).
        if let lang = codeBlock.language?.trimmingCharacters(in: .whitespaces),
           !lang.isEmpty {
            let labelP = NSMutableParagraphStyle()
            labelP.alignment = .right
            labelP.lineSpacing = 0
            labelP.textBlocks = [block]
            // The code body's paragraphSpacingBefore creates the cell's
            // vertical padding — none added on the label side.
            let labelFont = NSFont.monospacedSystemFont(
                ofSize: style.baseFontSize * 0.78, weight: .regular)
            let labelAttr = NSAttributedString(string: lang + "\n",
                                               attributes: [
                .font: labelFont,
                .foregroundColor: style.tertiary,
                .paragraphStyle: labelP,
            ])
            result.append(labelAttr)
        }

        let highlighted = MarkdownRenderer.syntaxHighlighter
            .highlight(code, language: codeBlock.language)

        let codeAttr: NSMutableAttributedString
        if let hl = highlighted {
            codeAttr = NSMutableAttributedString(attributedString: hl)
            let cr = NSRange(location: 0, length: codeAttr.length)
            // Highlightr's own `.backgroundColor` (the theme bg) doubles
            // dirtily with the textBlock bg — remove it.
            codeAttr.removeAttribute(.backgroundColor, range: cr)
            // Unify the font to SF Mono / baseFontSize while keeping bold /
            // italic traits.
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
                .foregroundColor: style.foreground,
            ])
        }
        // The cell ends with \n to terminate the paragraph (the textBlock
        // boundary). Without it, the next block joins the same paragraph and
        // the cell never closes.
        codeAttr.append(NSAttributedString(string: "\n"))
        let codeRange = NSRange(location: 0, length: codeAttr.length)
        codeAttr.addAttribute(.paragraphStyle, value: codeP, range: codeRange)

        result.append(codeAttr)
        return result
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> NSAttributedString {
        // Raw HTML stays as-is in monospace. HTML rendering is out of scope.
        let p = bodyParagraph()
        return NSAttributedString(string: html.rawHTML, attributes: [
            .font: monoFont,
            .foregroundColor: style.tertiary,
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

        // The GitHub-style left bar: a 1-cell NSTextTable with only the left
        // border thick and colored, other edges 0. A bare NSTextBlock breaks
        // layout — wrapping in a table is stable. collapsesBorders=true can
        // omit the border in the 1-cell case, so false to draw reliably.
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
        block.setBorderColor(style.blockquoteBar, for: .minX)
        // The gap between the left bar and the body + vertical breathing.
        block.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(4,  type: .absoluteValueType, for: .padding, edge: .maxX)
        block.setWidth(2,  type: .absoluteValueType, for: .padding, edge: .minY)
        block.setWidth(2,  type: .absoluteValueType, for: .padding, edge: .maxY)

        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.bodyLineSpacing
        p.textBlocks = [block]

        // \n closes the cell's paragraph (as in visitCodeBlock).
        inner.append(NSAttributedString(string: "\n"))
        let r = NSRange(location: 0, length: inner.length)
        inner.addAttribute(.paragraphStyle, value: p, range: r)
        inner.addAttribute(.foregroundColor,
                           value: style.tertiary, range: r)
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
            .foregroundColor: style.foreground,
            .paragraphStyle: p,
        ])
        let children = Array(item.children)
        for (index, child) in children.enumerated() {
            out.append(visit(child))
            if index < children.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: bodyAttrs()))
            }
        }
        // Wrapped lines and nested blocks align under the prefix.
        let r = NSRange(location: 0, length: out.length)
        out.enumerateAttribute(.paragraphStyle, in: r) { value, range, _ in
            let ps = (value as? NSParagraphStyle).flatMap {
                $0.mutableCopy() as? NSMutableParagraphStyle
            } ?? bodyParagraph()
            // Composing with existing indent: only the first line zeroes the
            // prefix's indent (`p.firstLineHeadIndent = 0`); the rest share
            // the same headIndent.
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
        // An hr is hard to produce with stock AppKit attributes in an
        // NSTextView, so lay U+2500 BOX DRAWINGS LIGHT HORIZONTAL across
        // roughly the width.
        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.bodyLineSpacing
        p.paragraphSpacing = style.bodyLineSpacing * 2
        p.paragraphSpacingBefore = style.bodyLineSpacing * 2
        return NSAttributedString(
            string: String(repeating: "─", count: 40),
            attributes: [
                .font: bodyFont,
                .foregroundColor: style.tertiary,
                .paragraphStyle: p,
            ])
    }

    /// GFM tables become "real rules" via NSTextTable + NSTextTableBlock —
    /// fundamentally avoiding the column drift monospace pseudo-rules hit
    /// with wide CJK glyphs. The header row gets a faint background + bold;
    /// each cell gets thin rules + padding for a sticky look.
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
        // Only the outer frame dark and thick: with collapsesBorders=true the
        // thicker of adjacent borders wins. Cells are 0.5pt subtle, the table
        // 1.2pt distinct → only the perimeter reads as a dark frame.
        textTable.setBorderColor(style.tableOuterBorder)
        textTable.setWidth(1.2, type: .absoluteValueType, for: .border)

        let out = NSMutableAttributedString()
        out.append(renderTableRow(head, columns: columns,
                                  rowIndex: 0, isHeader: true,
                                  table: textTable))
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
            // \n closes the cell's paragraph (as in visitCodeBlock).
            inner.append(NSAttributedString(string: "\n"))
            let r = NSRange(location: 0, length: inner.length)
            inner.addAttribute(.paragraphStyle, value: p, range: r)
            // Lay a font down for runs with none (empty cells).
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
        block.setBorderColor(style.border)
        block.setWidth(0.5, type: .absoluteValueType, for: .border)
        block.setWidth(8,   type: .absoluteValueType, for: .padding)
        if isHeader {
            block.backgroundColor = style.tableHeaderBackground
        }
        return block
    }

    private func applyTrait(_ trait: NSFontTraitMask, to s: NSMutableAttributedString) {
        let r = NSRange(location: 0, length: s.length)
        s.enumerateAttribute(.font, in: r) { value, range, _ in
            let original = (value as? NSFont) ?? bodyFont
            let traited = NSFontManager.shared.convert(original, toHaveTrait: trait)
            s.addAttribute(.font, value: traited, range: range)
        }
    }
}

/// A thin wrapper holding exactly one Highlightr (highlight.js +
/// JavaScriptCore) instance. The theme swaps from the CLI (`--theme`);
/// `--no-highlight` puts it in disabled mode, always returning nil (and
/// skipping the Highlightr boot). MarkupVisitor requires non-isolation, so
/// this stays non-isolated too.
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

    /// With a language hint, highlight as specified. Without one, do nothing
    /// and return nil (auto-detect breeds unintended highlighting — off).
    /// Disabled mode also always returns nil. The caller falls back to plain
    /// mono on nil.
    func highlight(_ code: String, language: String?) -> NSAttributedString? {
        guard !disabled else { return nil }
        let lang = (language ?? "").trimmingCharacters(in: .whitespaces)
        guard !lang.isEmpty else { return nil }
        return highlightr?.highlight(code, as: lang.lowercased(),
                                     fastRender: true)
    }
}
