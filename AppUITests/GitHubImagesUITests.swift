import XCTest

/// GitHub's image conventions in a real window: root-relative paths resolve against the git
/// work tree, and only one of a `#gh-light-mode-only` / `#gh-dark-mode-only` pair is shown.
@MainActor
final class GitHubImagesUITests: XCTestCase {
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

    /// A copy of the `github-images` fixture made into a git work tree (a `.git` folder can't be
    /// committed inside the project's own repository).
    private func copyRepository() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "mdv-ui-github-images-\(UUID().uuidString)", directoryHint: .isDirectory)
        self.folder = folder
        try FileManager.default.copyItem(at: try Fixtures.url(named: "github-images"), to: folder)
        try FileManager.default.createDirectory(at: folder.appending(path: ".git"), withIntermediateDirectories: true)
        return folder.appending(path: "docs/guide/README.md")
    }

    func testRootRelativeAndColorModeImages() throws {
        let mdv = MdvUITestApp.launch(opening: try copyRepository())
        self.mdv = mdv

        let window = mdv.waitForWindow(titled: "GitHub Images Fixture")
        mdv.waitForRenderedText("Images rendered.", in: window)
        assertImage("Root PNG", in: window, size: CGSize(width: 64, height: 48))
        assertImage("Root SVG", in: window, size: CGSize(width: 80, height: 30))

        let images = mdv.webView(in: window).images
        let shown = ["Light only", "Dark only"].filter { images[$0].exists }
        XCTAssertEqual(shown.count, 1, "exactly one appearance variant is shown: \(shown)")
        if let variant = shown.first {
            assertImage(variant, in: window, size: CGSize(width: 64, height: 48))
        }
    }

    private func assertImage(
        _ alt: String, in window: XCUIElement, size: CGSize, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let mdv else {
            return XCTFail("no app", file: file, line: line)
        }
        let image = mdv.webView(in: window).images[alt].firstMatch
        XCTAssertTrue(
            image.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "image \"\(alt)\"", file: file, line: line)
        let predicate = NSPredicate { object, _ in
            guard let frame = (object as? XCUIElement)?.frame else {
                return false
            }
            return abs(frame.width - size.width) <= 1 && abs(frame.height - size.height) <= 1
        }
        let loaded = XCTNSPredicateExpectation(predicate: predicate, object: image)
        XCTAssertEqual(
            XCTWaiter().wait(for: [loaded], timeout: MdvUITestApp.defaultTimeout), .completed,
            "image \"\(alt)\" frame \(image.frame.size), expected \(size)", file: file, line: line)
    }
}
