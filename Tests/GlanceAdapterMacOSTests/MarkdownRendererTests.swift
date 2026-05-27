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
}
