// CoreGraphics for CGRect's edge accessors / initializers (Foundation
// alone does not re-export them under the CLT toolchain). Still no AppKit.
import CoreGraphics
import Foundation

/// The panel's frame arithmetic with no AppKit in it, so XCTest covers it:
/// the auto-height clamp, anchor → frame (Cocoa Y-up), and the pull back
/// inside the screen. ViewerPanel measures the text and hands the numbers
/// here; the screen comes in as its `visibleFrame` (nil when headless).
public enum PanelGeometry {
    /// Where the panel goes with neither `--at` nor a screen to center on.
    public static let fallbackOrigin = CGPoint(x: 200, y: 200)

    /// Auto height = the text's natural height + the inset both sides + the
    /// title bar (none under `--hud`), clamped to Defaults' range. An
    /// explicit `--height` is honored as is — no clamp.
    public static func height(naturalTextHeight: CGFloat,
                              requested: CGFloat?,
                              hud: Bool) -> CGFloat {
        if let requested { return requested }
        let titleBarSlack = CGFloat(hud ? 0 : Defaults.titleBarSlack)
        let natural = ceil(naturalTextHeight)
            + CGFloat(Defaults.textInsetY) * 2
            + titleBarSlack
        let minH = CGFloat(hud ? Defaults.hudMinHeight : Defaults.minHeight)
        return min(max(natural, minH), CGFloat(Defaults.maxHeight))
    }

    /// The anchor is the panel's top-left and the panel extends downward,
    /// so the origin is `y - height`. Without an anchor the panel centers
    /// in `visibleFrame`; with no screen at all it sits at `fallbackOrigin`
    /// unclamped.
    public static func frame(size: CGSize,
                             anchor: Anchor?,
                             visibleFrame: CGRect?) -> CGRect {
        let base: CGRect
        if let anchor {
            base = CGRect(x: CGFloat(anchor.x),
                          y: CGFloat(anchor.y) - size.height,
                          width: size.width, height: size.height)
        } else if let vf = visibleFrame {
            base = CGRect(x: vf.midX - size.width / 2,
                          y: vf.midY - size.height / 2,
                          width: size.width, height: size.height)
        } else {
            base = CGRect(origin: fallbackOrigin, size: size)
        }
        guard let vf = visibleFrame else { return base }
        return clamp(base, to: vf)
    }

    /// Pulls a rect that dug into the screen edge back inside. Matters when
    /// the trigger's selection coordinates sit near the right or bottom
    /// edge. Max edges first, so a rect larger than the screen ends up
    /// flush with the min edge.
    public static func clamp(_ rect: CGRect, to vf: CGRect) -> CGRect {
        var r = rect
        if r.maxX > vf.maxX { r.origin.x = vf.maxX - r.width }
        if r.minX < vf.minX { r.origin.x = vf.minX }
        if r.maxY > vf.maxY { r.origin.y = vf.maxY - r.height }
        if r.minY < vf.minY { r.origin.y = vf.minY }
        return r
    }
}
