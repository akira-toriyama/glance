import XCTest
@testable import GlanceCore

final class PanelGeometryTests: XCTestCase {
    // A 4K-ish screen with the menu bar taken out, as NSScreen.visibleFrame
    // reports it; the measured `present: frame=` values in t-jyxe came from
    // this shape (center → (1730, 740) for 380×172).
    private let screen = CGRect(x: 0, y: 0, width: 3840, height: 1652)
    private let inset = CGFloat(Defaults.textInsetY) * 2

    func testAutoHeightAddsInsetsAndTitleBar() {
        XCTAssertEqual(
            PanelGeometry.height(naturalTextHeight: 100.2, requested: nil, hud: false),
            101 + inset + CGFloat(Defaults.titleBarSlack))
    }

    func testAutoHeightUnderHudHasNoTitleBar() {
        XCTAssertEqual(
            PanelGeometry.height(naturalTextHeight: 100, requested: nil, hud: true),
            100 + inset)
    }

    func testAutoHeightClampsToMin() {
        XCTAssertEqual(
            PanelGeometry.height(naturalTextHeight: 1, requested: nil, hud: false),
            CGFloat(Defaults.minHeight))
        XCTAssertEqual(
            PanelGeometry.height(naturalTextHeight: 1, requested: nil, hud: true),
            CGFloat(Defaults.hudMinHeight))
    }

    func testAutoHeightClampsToMax() {
        XCTAssertEqual(
            PanelGeometry.height(naturalTextHeight: 5000, requested: nil, hud: false),
            CGFloat(Defaults.maxHeight))
    }

    func testExplicitHeightIsNotClamped() {
        XCTAssertEqual(PanelGeometry.height(naturalTextHeight: 5000, requested: 1000, hud: false), 1000)
        XCTAssertEqual(PanelGeometry.height(naturalTextHeight: 5000, requested: 5, hud: true), 5)
    }

    func testAnchorIsTheTopLeft() {
        let f = PanelGeometry.frame(size: CGSize(width: 380, height: 172),
                                    anchor: Anchor(x: 800, y: 500),
                                    visibleFrame: screen)
        XCTAssertEqual(f, CGRect(x: 800, y: 328, width: 380, height: 172))
    }

    func testAnchorBelowTheBottomIsPulledUp() {
        let f = PanelGeometry.frame(size: CGSize(width: 380, height: 172),
                                    anchor: Anchor(x: 3000, y: 100),
                                    visibleFrame: screen)
        XCTAssertEqual(f, CGRect(x: 3000, y: 0, width: 380, height: 172))
    }

    func testAnchorOffTheBottomLeftIsPulledIn() {
        let f = PanelGeometry.frame(size: CGSize(width: 380, height: 112),
                                    anchor: Anchor(x: -50, y: -50),
                                    visibleFrame: screen)
        XCTAssertEqual(f, CGRect(x: 0, y: 0, width: 380, height: 112))
    }

    func testAnchorPastTheRightEdgeIsPulledLeft() {
        let f = PanelGeometry.frame(size: CGSize(width: 380, height: 172),
                                    anchor: Anchor(x: 3700, y: 1000),
                                    visibleFrame: screen)
        XCTAssertEqual(f.origin.x, 3840 - 380)
        XCTAssertEqual(f.origin.y, 828)
    }

    func testAnchorAboveTheTopIsPulledDown() {
        let f = PanelGeometry.frame(size: CGSize(width: 380, height: 172),
                                    anchor: Anchor(x: 10, y: 3000),
                                    visibleFrame: screen)
        XCTAssertEqual(f.origin.y, 1652 - 172)
    }

    func testCenteredWithoutAnchor() {
        let f = PanelGeometry.frame(size: CGSize(width: 380, height: 172),
                                    anchor: nil, visibleFrame: screen)
        XCTAssertEqual(f, CGRect(x: 1730, y: 740, width: 380, height: 172))
    }

    func testWiderThanTheScreenSitsFlushLeft() {
        let small = CGRect(x: 100, y: 0, width: 300, height: 800)
        let f = PanelGeometry.frame(size: CGSize(width: 380, height: 172),
                                    anchor: Anchor(x: 150, y: 500),
                                    visibleFrame: small)
        XCTAssertEqual(f.origin.x, 100)
    }

    func testNoScreenLeavesTheAnchorUnclamped() {
        let f = PanelGeometry.frame(size: CGSize(width: 380, height: 172),
                                    anchor: Anchor(x: -50, y: -50),
                                    visibleFrame: nil)
        XCTAssertEqual(f.origin, CGPoint(x: -50, y: -222))
    }

    func testNoScreenAndNoAnchorUsesTheFallbackOrigin() {
        let f = PanelGeometry.frame(size: CGSize(width: 380, height: 172),
                                    anchor: nil, visibleFrame: nil)
        XCTAssertEqual(f.origin, PanelGeometry.fallbackOrigin)
    }
}
