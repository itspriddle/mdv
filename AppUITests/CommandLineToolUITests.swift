import XCTest

/// App menu > Install / Uninstall Command Line Tool… (#70), over a temp folder passed with
/// `-MdvUITestCommandLineToolFolder` (never the real `/usr/local/bin` or `~/.local/bin`).
@MainActor
final class CommandLineToolUITests: XCTestCase {
    private var mdv: MdvUITestApp?
    private var folder: URL?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
        if let folder {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func launch() throws -> (MdvUITestApp, URL) {
        let folder = try MdvUITestApp.makeCommandLineToolFolder()
        self.folder = folder
        let mdv = try MdvUITestApp.launch(
            openingFixture: "live-reload.md", arguments: MdvUITestApp.commandLineToolFolderArguments(folder))
        self.mdv = mdv
        mdv.waitForWindow(titled: "Live Reload Fixture")
        return (mdv, folder.appending(path: "mdv"))
    }

    func testInstallThenUninstallFromAppMenu() throws {
        let (mdv, link) = try launch()

        mdv.clickAppMenuItem("Install Command Line Tool…")
        mdv.waitForAlertText("this copy of mdv")
        mdv.clickAlertButton("Install")
        mdv.waitForAlertText("The mdv command line tool is installed.")
        mdv.clickAlertButton("OK")

        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))
        XCTAssertTrue(destination.hasSuffix(".app/Contents/Helpers/mdv"), destination)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: link.path(percentEncoded: false)))

        mdv.clickAppMenuItem("Uninstall Command Line Tool…")
        mdv.waitForAlertText("This removes the link")
        mdv.clickAlertButton("Uninstall")
        let removed = NSPredicate { _, _ in
            (try? FileManager.default.attributesOfItem(atPath: link.path(percentEncoded: false))) == nil
        }
        let expectation = XCTNSPredicateExpectation(predicate: removed, object: nil)
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: MdvUITestApp.defaultTimeout), .completed,
            "the link was removed")

        // The item offers to install again.
        mdv.clickAppMenuItem("Install Command Line Tool…")
        mdv.clickAlertButton("Cancel")
    }

    func testFileInTheWayIsShownAndKept() throws {
        let (mdv, link) = try launch()
        try Data("not mdv".utf8).write(to: link)

        mdv.clickAppMenuItem("Install Command Line Tool…")
        mdv.clickAlertButton("Install")
        mdv.waitForAlertText("is already there: a file")
        mdv.clickAlertButton("OK")
        XCTAssertEqual(try String(contentsOf: link, encoding: .utf8), "not mdv")
    }
}
