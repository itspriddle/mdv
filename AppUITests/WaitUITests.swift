import XCTest

/// `mdv --wait FILE` (#69): the embedded CLI returns only once the windows it opened are closed,
/// or the app quits.
@MainActor
final class WaitUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    func testWaitsUntilTheWindowCloses() throws {
        let mdv = MdvUITestApp.launch()
        self.mdv = mdv
        let smoke = try MdvUITestApp.temporaryCopy(ofFixture: "smoke.md").path(percentEncoded: false)

        let waiting = try MdvUITestApp.startCommandLine(["--wait", smoke])
        let window = mdv.waitForWindow(titled: "Smoke Test Fixture")
        mdv.waitForRenderedText("The quick brown fox renders in mdv.", in: window)
        XCTAssertTrue(waiting.isStillRunning(after: 2), "mdv --wait returned with its window open")

        mdv.close(window)
        XCTAssertTrue(waiting.exits(within: MdvUITestApp.defaultTimeout), "mdv --wait didn't return")
        XCTAssertEqual(waiting.status, 0, waiting.stderr)
    }

    /// Each invocation waits on its own window, including one that was already open.
    func testConcurrentWaitsReturnOnTheirOwnWindows() throws {
        let mdv = MdvUITestApp.launch()
        self.mdv = mdv
        let smoke = try MdvUITestApp.temporaryCopy(ofFixture: "smoke.md").path(percentEncoded: false)
        let target = try MdvUITestApp.temporaryCopy(ofFixture: "links-target.md").path(percentEncoded: false)

        XCTAssertEqual(try MdvUITestApp.runCommandLine([smoke]).status, 0)
        let smokeWindow = mdv.waitForWindow(titled: "Smoke Test Fixture")
        let first = try MdvUITestApp.startCommandLine(["--wait", smoke])
        let second = try MdvUITestApp.startCommandLine(["--wait", target])
        let targetWindow = mdv.waitForWindow(titled: "Link Target")
        mdv.waitForWindowCount(2)
        XCTAssertTrue(first.isStillRunning(after: 1))
        XCTAssertTrue(second.process.isRunning)

        mdv.close(targetWindow)
        XCTAssertTrue(second.exits(within: MdvUITestApp.defaultTimeout), "the second wait didn't return")
        XCTAssertEqual(second.status, 0, second.stderr)
        XCTAssertTrue(first.isStillRunning(after: 1), "closing another window ended the first wait")

        mdv.close(smokeWindow)
        XCTAssertTrue(first.exits(within: MdvUITestApp.defaultTimeout), "the first wait didn't return")
        XCTAssertEqual(first.status, 0, first.stderr)
    }

    func testReturnsWhenTheAppQuits() throws {
        let mdv = MdvUITestApp.launch()
        self.mdv = mdv
        let smoke = try MdvUITestApp.temporaryCopy(ofFixture: "smoke.md").path(percentEncoded: false)

        let waiting = try MdvUITestApp.startCommandLine(["--wait", smoke])
        mdv.waitForWindow(titled: "Smoke Test Fixture")
        XCTAssertTrue(waiting.isStillRunning(after: 1))

        mdv.terminate()
        XCTAssertTrue(waiting.exits(within: MdvUITestApp.defaultTimeout), "mdv --wait outlived the app")
        XCTAssertEqual(waiting.status, 0, waiting.stderr)
    }
}
