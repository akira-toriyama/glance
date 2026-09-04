import XCTest
@testable import GlanceCore

final class HelpTextTests: XCTestCase {

    func testHelpQuotesTheVersionAndDefaults() {
        let help = HelpText.render(version: "9.9.9")
        XCTAssertTrue(help.hasPrefix("glance 9.9.9 — "))
        XCTAssertTrue(help.contains("(default \(Int(Defaults.width));"))
        XCTAssertTrue(help.contains("(default \(Int(Defaults.fontSize));"))
        XCTAssertTrue(help.contains(
            "clamped \(Int(Defaults.minHeight))–\(Int(Defaults.maxHeight))pt"))
        XCTAssertTrue(help.contains("(default\n"), "theme default wraps")
        XCTAssertTrue(help.contains("\(Defaults.theme))."))
    }

    func testHelpListsEveryFlagParseArgsAccepts() throws {
        let help = HelpText.render(version: "0")
        // Every flag parseArgs knows must be documented; unknown flags are
        // loud (exit 2), so an undocumented one is unreachable for users.
        let flags = ["--title", "--at", "--markdown", "--copy", "--auto-close",
                     "--width", "--height", "--font-size", "--theme",
                     "--no-highlight", "--hud", "--sticky", "--version",
                     "--help"]
        for flag in flags {
            XCTAssertTrue(help.contains("  \(flag)"), flag)
        }
        // And each documented flag really parses (a stale help line would
        // list a flag that no longer exists).
        for flag in ["--markdown", "--copy", "--no-highlight", "--hud", "--sticky"] {
            guard case .viewer = try parseArgs([flag]) else {
                return XCTFail("\(flag) no longer parses")
            }
        }
    }
}
