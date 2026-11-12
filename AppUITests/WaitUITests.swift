import XCTest

/// `peep --wait FILE` (#69): the embedded CLI returns only once the windows it opened are closed,
/// or the app quits.
@MainActor
final class WaitUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    func testWaitsUntilTheWindowCloses() throws {
        let peep = PeepUITestApp.launch()
        self.peep = peep
        let smoke = try PeepUITestApp.temporaryCopy(ofFixture: "smoke.md").path(percentEncoded: false)

        let waiting = try PeepUITestApp.startCommandLine(["--wait", smoke])
        let window = peep.waitForWindow(titled: "Smoke Test Fixture")
        peep.waitForRenderedText("The quick brown fox renders in Peep.", in: window)
        XCTAssertTrue(waiting.isStillRunning(after: 2), "peep --wait returned with its window open")

        peep.close(window)
        XCTAssertTrue(waiting.exits(within: PeepUITestApp.defaultTimeout), "peep --wait didn't return")
        XCTAssertEqual(waiting.status, 0, waiting.stderr)
    }

    /// Each invocation waits on its own window, including one that was already open.
    func testConcurrentWaitsReturnOnTheirOwnWindows() throws {
        let peep = PeepUITestApp.launch()
        self.peep = peep
        let smoke = try PeepUITestApp.temporaryCopy(ofFixture: "smoke.md").path(percentEncoded: false)
        let target = try PeepUITestApp.temporaryCopy(ofFixture: "links-target.md").path(percentEncoded: false)

        XCTAssertEqual(try PeepUITestApp.runCommandLine([smoke]).status, 0)
        let smokeWindow = peep.waitForWindow(titled: "Smoke Test Fixture")
        let first = try PeepUITestApp.startCommandLine(["--wait", smoke])
        let second = try PeepUITestApp.startCommandLine(["--wait", target])
        let targetWindow = peep.waitForWindow(titled: "Link Target")
        peep.waitForWindowCount(2)
        XCTAssertTrue(first.isStillRunning(after: 1))
        XCTAssertTrue(second.process.isRunning)

        peep.close(targetWindow)
        XCTAssertTrue(second.exits(within: PeepUITestApp.defaultTimeout), "the second wait didn't return")
        XCTAssertEqual(second.status, 0, second.stderr)
        XCTAssertTrue(first.isStillRunning(after: 1), "closing another window ended the first wait")

        peep.close(smokeWindow)
        XCTAssertTrue(first.exits(within: PeepUITestApp.defaultTimeout), "the first wait didn't return")
        XCTAssertEqual(first.status, 0, first.stderr)
    }

    func testReturnsWhenTheAppQuits() throws {
        let peep = PeepUITestApp.launch()
        self.peep = peep
        let smoke = try PeepUITestApp.temporaryCopy(ofFixture: "smoke.md").path(percentEncoded: false)

        let waiting = try PeepUITestApp.startCommandLine(["--wait", smoke])
        peep.waitForWindow(titled: "Smoke Test Fixture")
        XCTAssertTrue(waiting.isStillRunning(after: 1))

        peep.terminate()
        XCTAssertTrue(waiting.exits(within: PeepUITestApp.defaultTimeout), "peep --wait outlived the app")
        XCTAssertEqual(waiting.status, 0, waiting.stderr)
    }
}
