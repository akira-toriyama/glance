import AppKit

/// NSLayoutManager subclass。`.backgroundColor` attribute が指定された range
/// (= inline code) を角丸の "pill" として描画する。NSTextTable cell の bg は
/// `paragraphStyle.textBlocks` 経由で別系統で描かれるためここを通らないので
/// 影響しない (code block / blockquote / table はそのまま矩形)。
///
/// TextKit 1 (NSLayoutManager) のみ。NSTextView を `init(frame:textContainer:)`
/// で明示構築すると TextKit 1 が選択され、本クラスの override が効く。
final class GlanceLayoutManager: NSLayoutManager {

    /// pill の角丸半径。文字 1 文字分くらいの浅い rounding。
    static let cornerRadius: CGFloat = 4

    /// 文字幅の左右に追加する pill padding。`backgroundColor` attr は
    /// 文字の advance 範囲しか持たないので、視覚的に呼吸を入れるために
    /// 左右へ少し膨らませる。
    static let horizontalInset: CGFloat = -3

    /// 縦方向の膨らみ。デフォルト 0 (行高ぴったり)。
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
