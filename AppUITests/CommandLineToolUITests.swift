import XCTest

/// App menu > Install / Uninstall Command Line Tool… (#70), over a temp folder passed with
/// `-PeepUITestCommandLineToolFolder` (never the real `/usr/local/bin` or `~/.local/bin`).
@MainActor
final class CommandLineToolUITests: XCTestCase {
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

    private func launch() throws -> (PeepUITestApp, URL) {
        let folder = try PeepUITestApp.makeCommandLineToolFolder()
        self.folder = folder
        let peep = try PeepUITestApp.launch(
            openingFixture: "live-reload.md", arguments: PeepUITestApp.commandLineToolFolderArguments(folder))
        self.peep = peep
        peep.waitForWindow(titled: "Live Reload Fixture")
        return (peep, folder.appending(path: "peep"))
    }

    func testInstallThenUninstallFromAppMenu() throws {
        let (peep, link) = try launch()

        peep.clickAppMenuItem("Install Command Line Tool…")
        peep.waitForAlertText("this copy of Peep")
        peep.clickAlertButton("Install")
        peep.waitForAlertText("The Peep command line tool is installed.")
        peep.clickAlertButton("OK")

        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))
        XCTAssertTrue(destination.hasSuffix(".app/Contents/Helpers/peep"), destination)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: link.path(percentEncoded: false)))

        peep.clickAppMenuItem("Uninstall Command Line Tool…")
        peep.waitForAlertText("This removes the link")
        peep.clickAlertButton("Uninstall")
        let removed = NSPredicate { _, _ in
            (try? FileManager.default.attributesOfItem(atPath: link.path(percentEncoded: false))) == nil
        }
        let expectation = XCTNSPredicateExpectation(predicate: removed, object: nil)
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: PeepUITestApp.defaultTimeout), .completed,
            "the link was removed")

        // The item offers to install again.
        peep.clickAppMenuItem("Install Command Line Tool…")
        peep.clickAlertButton("Cancel")
    }

    func testFileInTheWayIsShownAndKept() throws {
        let (peep, link) = try launch()
        try Data("not Peep".utf8).write(to: link)

        peep.clickAppMenuItem("Install Command Line Tool…")
        peep.clickAlertButton("Install")
        peep.waitForAlertText("is already there: a file")
        peep.clickAlertButton("OK")
        XCTAssertEqual(try String(contentsOf: link, encoding: .utf8), "not Peep")
    }
}
