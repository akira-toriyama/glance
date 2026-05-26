import XCTest
@testable import GlanceCore

final class ArgsTests: XCTestCase {

    // MARK: parse — basic flags

    func testEmptyArgsReturnsViewerWithDefaults() throws {
        let result = try parseArgs([])
        guard case .viewer(let a) = result else {
            return XCTFail("expected .viewer, got \(result)")
        }
        XCTAssertEqual(a.title, "")
        XCTAssertNil(a.atX)
        XCTAssertNil(a.atY)
        XCTAssertFalse(a.markdown)
        XCTAssertNil(a.autoCloseSeconds)
    }

    func testHelpReturnsShowHelp() throws {
        if case .showHelp = try parseArgs(["--help"]) {} else {
            XCTFail("expected .showHelp")
        }
        if case .showHelp = try parseArgs(["-h"]) {} else {
            XCTFail("expected .showHelp for -h")
        }
    }

    func testVersionReturnsShowVersion() throws {
        if case .showVersion = try parseArgs(["--version"]) {} else {
            XCTFail("expected .showVersion")
        }
        if case .showVersion = try parseArgs(["-V"]) {} else {
            XCTFail("expected .showVersion for -V")
        }
    }

    func testTitleFlag() throws {
        guard case .viewer(let a) = try parseArgs(
            ["--title", "Hello world"]) else {
            return XCTFail("expected .viewer")
        }
        XCTAssertEqual(a.title, "Hello world")
    }

    func testAtFlagWithTwoNumbers() throws {
        guard case .viewer(let a) = try parseArgs(
            ["--at", "800", "500"]) else {
            return XCTFail("expected .viewer")
        }
        XCTAssertEqual(a.atX, 800)
        XCTAssertEqual(a.atY, 500)
    }

    func testMarkdownFlag() throws {
        guard case .viewer(let a) = try parseArgs(["--markdown"]) else {
            return XCTFail("expected .viewer")
        }
        XCTAssertTrue(a.markdown)
    }

    func testAutoCloseFlag() throws {
        guard case .viewer(let a) = try parseArgs(
            ["--auto-close", "3.5"]) else {
            return XCTFail("expected .viewer")
        }
        XCTAssertEqual(a.autoCloseSeconds, 3.5)
    }

    func testWidthAndHeightFlags() throws {
        guard case .viewer(let a) = try parseArgs(
            ["--width", "500", "--height", "300"]) else {
            return XCTFail("expected .viewer")
        }
        XCTAssertEqual(a.width, 500)
        XCTAssertEqual(a.height, 300)
    }

    func testCombinedFlags() throws {
        guard case .viewer(let a) = try parseArgs(
            ["--title", "T", "--at", "10", "20", "--markdown"]) else {
            return XCTFail("expected .viewer")
        }
        XCTAssertEqual(a.title, "T")
        XCTAssertEqual(a.atX, 10)
        XCTAssertEqual(a.atY, 20)
        XCTAssertTrue(a.markdown)
    }

    // MARK: parse — error cases

    func testMissingTitleValue() {
        XCTAssertThrowsError(try parseArgs(["--title"])) { error in
            XCTAssertEqual(error as? ArgsParseError,
                           .missingValue("--title"))
        }
    }

    func testAtMissingSecondNumber() {
        XCTAssertThrowsError(try parseArgs(["--at", "100"])) { error in
            XCTAssertEqual(error as? ArgsParseError,
                           .missingValue("--at"))
        }
    }

    func testAtInvalidNumber() {
        XCTAssertThrowsError(
            try parseArgs(["--at", "abc", "100"])) { error in
            XCTAssertEqual(error as? ArgsParseError,
                           .invalidNumber("--at", "abc"))
        }
    }

    func testAutoCloseInvalidNumber() {
        XCTAssertThrowsError(
            try parseArgs(["--auto-close", "nope"])) { error in
            XCTAssertEqual(error as? ArgsParseError,
                           .invalidNumber("--auto-close", "nope"))
        }
    }

    func testUnknownFlag() {
        XCTAssertThrowsError(try parseArgs(["--bogus"])) { error in
            XCTAssertEqual(error as? ArgsParseError,
                           .unknownFlag("--bogus"))
        }
    }
}
