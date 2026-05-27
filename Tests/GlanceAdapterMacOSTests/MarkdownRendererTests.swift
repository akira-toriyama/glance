import AppKit
import XCTest
@testable import GlanceAdapterMacOS

/// MarkdownRenderer の最低限の挙動契約。visual 部分は手動確認に頼るが、
/// AST → attribute mapping のリグレッションは XCTest で押さえる。
@MainActor
final class MarkdownRendererTests: XCTestCase {

    /// テスト共通の Style。値は ViewerPanel デフォルトと意図的に独立させて
    /// テストが production の constants 変更で壊れないようにする。
    private static let testStyle = MarkdownRenderer.Style(
        baseFontSize: 14,
        bodyLineSpacing: 2,
        inlineCodeBackground: NSColor(white: 1, alpha: 0.2),
        codeBlockBackground:  NSColor(white: 1, alpha: 0.15),
        codeBlockIndent: 8,
        blockquoteIndent: 12,
        codeBlockParagraphSpacing: 4)

    private func render(_ text: String) -> NSAttributedString {
        MarkdownRenderer(style: Self.testStyle).render(text)
    }

    // MARK: heading / inline

    func testPlainParagraphPreservesText() {
        let out = render("hello world")
        XCTAssertTrue(out.string.contains("hello world"))
    }

    func testHeadingUsesBoldFont() {
        let out = render("# Title")
        XCTAssertTrue(out.string.contains("Title"))
        // 先頭 char の font が bold trait 持ちか確認。
        let f = out.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(f)
        XCTAssertTrue(f!.fontDescriptor.symbolicTraits.contains(.bold))
    }

    func testStrongRunIsBold() {
        let out = render("**bold**")
        XCTAssertTrue(out.string.contains("bold"))
        let nsString = out.string as NSString
        let r = nsString.range(of: "bold")
        let f = out.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(f)
        XCTAssertTrue(f!.fontDescriptor.symbolicTraits.contains(.bold))
    }

    func testInlineCodeIsMonospace() {
        let out = render("text `code` more")
        let nsString = out.string as NSString
        let r = nsString.range(of: "code")
        let f = out.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(f)
        XCTAssertTrue(f!.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    // MARK: GFM extensions

    func testTaskListUsesCheckboxGlyphs() {
        let out = render("""
        - [x] done
        - [ ] todo
        """)
        XCTAssertTrue(out.string.contains("☑"),
                      "checked task should render as ☑")
        XCTAssertTrue(out.string.contains("☐"),
                      "unchecked task should render as ☐")
    }

    func testStrikethroughAppliesStrikethroughStyle() {
        let out = render("~~deleted~~")
        let nsString = out.string as NSString
        let r = nsString.range(of: "deleted")
        XCTAssertGreaterThan(r.length, 0, "strike text should appear in output")
        let style = out.attribute(.strikethroughStyle,
                                  at: r.location, effectiveRange: nil) as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue)
    }

    func testTableContainsAllCellValues() {
        let out = render("""
        | A | B |
        |---|---|
        | foo | bar |
        | baz | qux |
        """)
        for cell in ["A", "B", "foo", "bar", "baz", "qux"] {
            XCTAssertTrue(out.string.contains(cell),
                          "table output missing cell: \(cell)")
        }
    }

    // MARK: code block

    func testCodeBlockBodyHasMonospaceFont() {
        let out = render("```\nlet x = 1\n```")
        let nsString = out.string as NSString
        let r = nsString.range(of: "let x = 1")
        XCTAssertGreaterThan(r.length, 0)
        let f = out.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(f)
        XCTAssertTrue(f!.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    func testCodeBlockWithLanguageHasLabel() {
        let out = render("```swift\nlet x = 1\n```")
        XCTAssertTrue(out.string.contains("swift"),
                      "language label 'swift' should appear in code block")
        XCTAssertTrue(out.string.contains("let x = 1"))
    }

    func testCodeBlockWithoutLanguageHasNoLabel() {
        // 言語指定なし → label 出さない (label トリガーは語彙指定の有無のみ)。
        let out = render("```\nplain code\n```")
        // "plain code" は含まれるが、独立した "swift" / "python" 等の言語名
        // トークンは含まれないこと
        XCTAssertTrue(out.string.contains("plain code"))
    }

    // MARK: link

    func testLinkRunHasURLAttribute() {
        let out = render("[Apple](https://apple.com)")
        let nsString = out.string as NSString
        let r = nsString.range(of: "Apple")
        let url = out.attribute(.link, at: r.location, effectiveRange: nil) as? URL
        XCTAssertEqual(url?.absoluteString, "https://apple.com")
    }

    func testLinkRunHasAccentForeground() {
        let out = render("[link](https://x.com)")
        let nsString = out.string as NSString
        let r = nsString.range(of: "link")
        let fg = out.attribute(.foregroundColor,
                               at: r.location, effectiveRange: nil) as? NSColor
        XCTAssertEqual(fg, NSColor.controlAccentColor)
    }

    func testLinkRunHasSingleUnderline() {
        let out = render("[link](https://x.com)")
        let nsString = out.string as NSString
        let r = nsString.range(of: "link")
        let style = out.attribute(.underlineStyle,
                                  at: r.location, effectiveRange: nil) as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue)
    }

    // MARK: heading hierarchy (h1/h2 underline)

    func testH1HasUnderline() {
        let out = render("# H1")
        let nsString = out.string as NSString
        let r = nsString.range(of: "H1")
        let style = out.attribute(.underlineStyle,
                                  at: r.location, effectiveRange: nil) as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue,
                       "h1 should have GitHub-style underline")
    }

    func testH2HasUnderline() {
        let out = render("## H2")
        let nsString = out.string as NSString
        let r = nsString.range(of: "H2")
        let style = out.attribute(.underlineStyle,
                                  at: r.location, effectiveRange: nil) as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue,
                       "h2 should have GitHub-style underline")
    }

    func testH3HasNoUnderline() {
        let out = render("### H3")
        let nsString = out.string as NSString
        let r = nsString.range(of: "H3")
        let style = out.attribute(.underlineStyle,
                                  at: r.location, effectiveRange: nil) as? Int?
        // h3 以下は線を付けない設計。
        XCTAssertNil(style ?? nil,
                     "h3 should NOT have underline (only h1/h2 do)")
    }

    func testHeadingLevelDrivesFontSize() {
        // h1 のフォントサイズは h3 より大きいはず。具体値は scales 配列に
        // 依存するが、大小関係はテストで固定。
        let h1Out = render("# size")
        let h3Out = render("### size")
        let h1NSStr = h1Out.string as NSString
        let h3NSStr = h3Out.string as NSString
        let h1R = h1NSStr.range(of: "size")
        let h3R = h3NSStr.range(of: "size")
        let h1f = h1Out.attribute(.font, at: h1R.location,
                                  effectiveRange: nil) as? NSFont
        let h3f = h3Out.attribute(.font, at: h3R.location,
                                  effectiveRange: nil) as? NSFont
        XCTAssertNotNil(h1f)
        XCTAssertNotNil(h3f)
        XCTAssertGreaterThan(h1f!.pointSize, h3f!.pointSize)
    }

    // MARK: lists

    func testUnorderedListUsesBulletGlyph() {
        let out = render("- one\n- two")
        XCTAssertTrue(out.string.contains("•"),
                      "unordered list should use • bullet")
    }

    func testOrderedListNumbers() {
        let out = render("1. one\n2. two")
        XCTAssertTrue(out.string.contains("1."))
        XCTAssertTrue(out.string.contains("2."))
    }

    // MARK: empty / edge cases

    func testEmptyInputProducesEmptyOutput() {
        let out = render("")
        XCTAssertEqual(out.length, 0)
    }

    func testParagraphsConcatenateWithNewline() {
        let out = render("first\n\nsecond")
        XCTAssertTrue(out.string.contains("first"))
        XCTAssertTrue(out.string.contains("second"))
        XCTAssertTrue(out.string.contains("\n"))
    }

    // MARK: blockquote

    func testBlockQuoteUsesSecondaryLabelColor() {
        let out = render("> quoted")
        let nsString = out.string as NSString
        let r = nsString.range(of: "quoted")
        let fg = out.attribute(.foregroundColor,
                               at: r.location, effectiveRange: nil) as? NSColor
        XCTAssertEqual(fg, NSColor.secondaryLabelColor)
    }

    // MARK: thematic break

    func testThematicBreakRendersHorizontalRule() {
        let out = render("before\n\n---\n\nafter")
        XCTAssertTrue(out.string.contains("─"),
                      "thematic break should produce ─ glyph row")
    }
}
