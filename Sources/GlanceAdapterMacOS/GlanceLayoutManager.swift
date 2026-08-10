import AppKit

/// An NSLayoutManager subclass drawing any range carrying a
/// `.backgroundColor` attribute (= inline code) as a rounded "pill".
/// NSTextTable cell backgrounds are drawn by a separate path via
/// `paragraphStyle.textBlocks` and never come through here, so they are
/// unaffected (code blocks / blockquotes / tables stay rectangular).
///
/// TextKit 1 (NSLayoutManager) only. Constructing the NSTextView explicitly
/// with `init(frame:textContainer:)` selects TextKit 1, making this class's
/// overrides effective.
final class GlanceLayoutManager: NSLayoutManager {

    /// The pill's corner radius — shallow rounding, about one character.
    static let cornerRadius: CGFloat = 4

    /// Horizontal pill padding beyond the glyph advance. The
    /// `backgroundColor` attr only spans the characters' advance range, so
    /// bulge slightly left and right for visual breathing room.
    static let horizontalInset: CGFloat = -3

    /// Vertical bulge. Default 0 (exactly line height).
    static let verticalInset: CGFloat = 0

    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<NSRect>,
        count rectCount: Int,
        forCharacterRange charRange: NSRange,
        color: NSColor
    ) {
        color.set()
        for i in 0..<rectCount {
            let rect = rectArray[i]
                .insetBy(dx: Self.horizontalInset, dy: Self.verticalInset)
            let path = NSBezierPath(
                roundedRect: rect,
                xRadius: Self.cornerRadius,
                yRadius: Self.cornerRadius)
            path.fill()
        }
    }
}
