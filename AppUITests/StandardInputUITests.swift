import XCTest

/// `cmd | peep` (#68): the embedded CLI hands standard input to the running app, which shows it
/// in an untitled window and deletes the handoff file. Each run gets its own `TMPDIR`, so the
/// test can see that nothing is left behind.
@MainActor
final class StandardInputUITests: XCTestCase {
    private var peep: PeepUITestApp?
    private var folder: URL?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
        if let folder {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// A new folder holding `handoffs` (the CLI's `TMPDIR`) and any input files.
    private func makeFolder() throws -> (inputs: URL, handoffs: URL) {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-ui-stdin-\(UUID().uuidString)", directoryHint: .isDirectory)
        self.folder = folder
        let handoffs = folder.appending(path: "tmp", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: handoffs, withIntermediateDirectories: true)
        return (folder, handoffs)
    }

    private func contents(of folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
    }

    func testPipedInputOpensWindowsAndLeavesNoFiles() throws {
        let peep = PeepUITestApp.launch()
        self.peep = peep
        let (inputs, handoffs) = try makeFolder()
        let environment = ["TMPDIR": handoffs.path(percentEncoded: false)]

        // `peep < smoke.md`
        let piped = try PeepUITestApp.runCommandLine(
            [], standardInput: try Fixtures.url(named: "smoke.md"), environment: environment)
        XCTAssertEqual(piped.status, 0, piped.stderr)
        let window = peep.waitForWindow(titled: "Smoke Test Fixture")
        peep.waitForRenderedText("The quick brown fox renders in Peep.", in: window)
        XCTAssertEqual(try contents(of: handoffs), [], "the app deleted the handoff once it read it")

        // README: `echo '# Markdown' | peep`
        let echo = inputs.appending(path: "echo.txt")
        try Data("# Markdown\n".utf8).write(to: echo)
        let readme = try PeepUITestApp.runCommandLine([], standardInput: echo, environment: environment)
        XCTAssertEqual(readme.status, 0, readme.stderr)
        peep.waitForWindow(titled: "Markdown")
        peep.waitForWindowCount(2)
        XCTAssertEqual(try contents(of: handoffs), [])

        peep.frontWindow.typeKey("w", modifierFlags: .command)
        peep.frontWindow.typeKey("w", modifierFlags: .command)
        peep.waitForWindowCount(0)
        XCTAssertEqual(try contents(of: handoffs), [], "nothing appears after the windows close")
    }

    /// `cmd | peep --wait` (#68 with #69): returns once the standard input window closes.
    func testWaitReturnsWhenTheStandardInputWindowCloses() throws {
        let peep = PeepUITestApp.launch()
        self.peep = peep
        let (inputs, handoffs) = try makeFolder()
        let input = inputs.appending(path: "waited.txt")
        try Data("# Waited For\n\nPiped and waited.\n".utf8).write(to: input)

        let waiting = try PeepUITestApp.startCommandLine(
            ["--wait"], standardInput: input, environment: ["TMPDIR": handoffs.path(percentEncoded: false)])
        let window = peep.waitForWindow(titled: "Waited For")
        peep.waitForRenderedText("Piped and waited.", in: window)
        XCTAssertTrue(waiting.isStillRunning(after: 2), "peep --wait returned with its window open")
        XCTAssertEqual(try contents(of: handoffs), [])

        peep.close(window)
        XCTAssertTrue(waiting.exits(within: PeepUITestApp.defaultTimeout), "peep --wait didn't return")
        XCTAssertEqual(waiting.status, 0, waiting.stderr)
    }

    func testEmptyOversizeAndInvalidInputOpenNothing() throws {
        let peep = PeepUITestApp.launch()
        self.peep = peep
        let (inputs, handoffs) = try makeFolder()
        let environment = ["TMPDIR": handoffs.path(percentEncoded: false)]
        let cases = [
            BadInput(name: "empty.md", data: Data(), status: 66, message: "empty"),
            BadInput(
                name: "large.md", data: Data(repeating: 0x61, count: 10 * 1024 * 1024 + 1), status: 65,
                message: "larger than 10 MB"),
            BadInput(name: "binary.md", data: Data([0x23, 0x20, 0xFF, 0xFE]), status: 65, message: "not valid UTF-8"),
        ]
        for input in cases {
            let file = inputs.appending(path: input.name)
            try input.data.write(to: file)
            let result = try PeepUITestApp.runCommandLine([], standardInput: file, environment: environment)
            XCTAssertEqual(result.status, input.status, input.name)
            XCTAssertTrue(result.stderr.contains(input.message), result.stderr)
        }
        XCTAssertFalse(peep.app.windows.firstMatch.waitForExistence(timeout: 2), "no window opened")
        XCTAssertEqual(try contents(of: handoffs), [])
    }
}

/// Standard input the CLI refuses, with its exit status and part of its message.
private struct BadInput {
    let name: String
    let data: Data
    let status: Int32
    let message: String
}
