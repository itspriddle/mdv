import XCTest

/// Opening a large document (#32): its window appears and renders off the main thread, and a
/// small document opened with it isn't held up behind the render.
@MainActor
final class LargeDocumentUITests: XCTestCase {
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

    /// Writes about 5 MB of Markdown titled "Large Document" (a heading every few KB).
    private func writeLargeDocument() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-ui-large-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        let section = (1...4).map { _ in
            """
            Paragraph with *emphasis*, **strong**, `code`, and a [link](https://example.com/). Lorem ipsum \
            dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore.

            - item one
            - item two

            ```swift
            let value = [1, 2, 3].map { $0 * 2 }
            ```


            """
        }.joined()
        var source = "# Large Document\n\n"
        var index = 0
        while source.utf8.count < 5_000_000 {
            index += 1
            source += "## Section \(index)\n\n" + section
        }
        let file = folder.appending(path: "large.md")
        try Data(source.utf8).write(to: file)
        return file
    }

    func testLargeDocumentRendersWithoutHoldingUpOtherWindows() throws {
        let large = try writeLargeDocument()
        let small = try Fixtures.url(named: "smoke.md")
        let peep = PeepUITestApp.launch(arguments: [
            "-PeepUITestOpen",
            PeepUITestApp.propertyListArray([large, small].map { $0.path(percentEncoded: false) }),
        ])
        self.peep = peep

        // The small document opens and renders while the large one is still rendering (or
        // done, on a fast machine); either way the large one's window is up, titled with the
        // file name until its render lands. Waiting for that window, rather than for a window
        // count, avoids `windows.count`, which snapshots the whole app, the 5 MB page included,
        // on every poll: once it failed with both windows listed, the snapshots outlasting the
        // default timeout while the large page loaded.
        let smallWindow = peep.waitForWindow(titled: "Smoke Test Fixture", timeout: 30)
        peep.waitForRenderedText("The quick brown fox renders in Peep.", in: smallWindow)
        let largeWindow = peep.app.windows.matching(
            NSPredicate(format: "title IN %@", ["large.md", "Large Document"])
        ).firstMatch
        XCTAssertTrue(largeWindow.waitForExistence(timeout: 30), "the large document's window is up")

        // The large document's window takes its title from the render once it lands. Its page
        // isn't queried: the accessibility tree of a 5 MB page is too slow to snapshot.
        peep.waitForWindow(titled: "Large Document", timeout: 60)
    }
}
