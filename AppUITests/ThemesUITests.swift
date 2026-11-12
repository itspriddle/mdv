import XCTest

/// The bundled themes (#33) and the theme picker (#34). The showcase test opens the fixture (`themes/showcase.md`, every construct a theme styles) that
/// manual checks and the visual regression check (#39) use.
@MainActor
final class ThemesUITests: XCTestCase {
    private var peep: PeepUITestApp?
    private var themesFolder: URL?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
        if let themesFolder {
            try? FileManager.default.removeItem(at: themesFolder)
        }
    }

    func testShowcaseFixtureRendersInDefaultTheme() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "themes/showcase.md")
        self.peep = peep

        let window = peep.waitForWindow(titled: "Theme Showcase")
        peep.waitForWebView(in: window)
        peep.waitForRenderedText("Third-level heading", in: window)
        peep.waitForRenderedText("Text after a thematic break. Theme showcase ends here.", in: window)
    }

    /// View > Theme switches the window's theme in place: the text reflows in the new theme's
    /// font, and the paragraph at the top of the view stays there (no reload to the top).
    func testThemeSwitchRestylesInPlaceAndKeepsPosition() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "live-reload.md")
        self.peep = peep
        let window = peep.waitForWindow(titled: "Live Reload Fixture")
        let webView = peep.webView(in: window)
        peep.waitForRenderedText("Paragraph 1.", in: window)

        for _ in 0..<4 {
            webView.typeKey(.pageDown, modifierFlags: [])
        }
        let anchor = try XCTUnwrap(peep.firstVisibleText(startingWith: "Paragraph ", in: window))
        let label = anchor.displayedText
        XCTAssertNotEqual(label, "Paragraph 1.", "the view scrolled")
        let before = anchor.frame

        peep.chooseTheme("Serif")

        // The computed style changed: the same text run has another size in the serif font.
        let paragraph = peep.renderedText(label, in: window)
        let restyled = NSPredicate { _, _ in abs(paragraph.frame.width - before.width) > 1 }
        XCTAssertEqual(
            XCTWaiter().wait(
                for: [XCTNSPredicateExpectation(predicate: restyled, object: nil)],
                timeout: PeepUITestApp.defaultTimeout),
            .completed, "\(label) kept its width \(before.width)")
        // Same paragraph at the top of the view: the stylesheet was swapped, not the page reloaded.
        XCTAssertTrue(paragraph.exists)
        // Within about a line: the new font reflows the paragraph around the kept source line
        // (9 pt off on macOS 26); a reload would put Paragraph 1 at the top instead.
        XCTAssertEqual(paragraph.frame.minY, before.minY, accuracy: 24, "\(label) moved")
    }

    /// Custom themes (#35): a CSS file in the themes folder is listed in View > Theme; editing
    /// it restyles the window that shows it, a file added while the app runs is listed too, and
    /// deleting the theme in use falls back to the default.
    func testCustomThemeAppearsAndUpdatesLive() throws {
        let folder = try PeepUITestApp.makeThemesFolder()
        themesFolder = folder
        let theme = folder.appending(path: "big.css")
        try Data("/* peep-theme\nname: UI Test Big\n*/\n.markdown-body p { font-size: 40px; }\n".utf8).write(to: theme)

        let peep = try PeepUITestApp.launch(
            openingFixture: "live-reload.md", arguments: PeepUITestApp.themesFolderArguments(folder))
        self.peep = peep
        let window = peep.waitForWindow(titled: "Live Reload Fixture")
        let paragraph = peep.waitForRenderedText("Paragraph 1.", in: window)
        let defaultWidth = paragraph.frame.width

        XCTAssertTrue(peep.waitForThemeMenuItem("UI Test Big"), "the custom theme is listed")
        peep.chooseTheme("UI Test Big")
        waitUntil("the custom theme's large text") { paragraph.frame.width > defaultWidth * 2 }
        let bigWidth = paragraph.frame.width

        // Edited on disk: the open window restyles without a restart.
        try Data("/* peep-theme\nname: UI Test Big\n*/\n.markdown-body p { font-size: 24px; }\n".utf8).write(
            to: theme, options: .atomic)
        waitUntil("the edited theme's smaller text") {
            paragraph.frame.width < bigWidth * 0.8 && paragraph.frame.width > defaultWidth * 1.2
        }

        // Added while running: listed.
        try Data("p { color: gray; }\n".utf8).write(to: folder.appending(path: "UI Test Added.css"))
        XCTAssertTrue(peep.waitForThemeMenuItem("UI Test Added"), "a theme added while the app runs is listed")

        // Deleted while in use: back to the default theme.
        try FileManager.default.removeItem(at: theme)
        waitUntil("the default theme's text size") { abs(paragraph.frame.width - defaultWidth) < 2 }
    }

    /// Frontmatter overrides (#54): a document with `peep: { theme: serif }` opens in Serif. A
    /// pick from View > Theme beats it, and View > Theme > Document's Theme goes back to it.
    func testFrontmatterThemeOpensInThatTheme() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "document-theme.md")
        self.peep = peep
        let window = peep.waitForWindow(titled: "Document Theme Fixture")
        let paragraph = peep.waitForRenderedText("This paragraph is set in the theme", in: window)
        let documentWidth = paragraph.frame.width

        peep.chooseTheme("GitHub")
        waitUntil("GitHub restyles the paragraph") { abs(paragraph.frame.width - documentWidth) > 1 }

        peep.chooseDocumentTheme()
        waitUntil("back to the document's theme") { abs(paragraph.frame.width - documentWidth) < 1 }

        // The document's theme was Serif: picking Serif leaves the paragraph as it opened.
        peep.chooseTheme("GitHub")
        waitUntil("GitHub again") { abs(paragraph.frame.width - documentWidth) > 1 }
        peep.chooseTheme("Serif")
        waitUntil("Serif matches how it opened") { abs(paragraph.frame.width - documentWidth) < 1 }
    }

    private func waitUntil(_ description: String, _ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        XCTAssertEqual(
            XCTWaiter().wait(
                for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)],
                timeout: PeepUITestApp.defaultTimeout),
            .completed, description)
    }
}
