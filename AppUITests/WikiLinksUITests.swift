import XCTest

/// Wiki links (#53) in the running app: a found page opens in Peep when clicked, a missing one
/// does nothing, and Settings > Markdown turns them on for open documents.
@MainActor
final class WikiLinksUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    func testClickingWikiLinkOpensTarget() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "wiki-links/index.md")
        self.peep = peep
        let window = peep.waitForWindow(titled: "Wiki Index")
        peep.waitForRenderedText("Go to", in: window)

        peep.link("the wiki target", in: window).click()
        let target = peep.waitForWindow(titled: "Wiki Target")
        peep.waitForRenderedText("Target page text.", in: target)
        XCTAssertTrue(peep.window(titled: "Wiki Index").exists)
    }

    func testMissingWikiLinkDoesNothing() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "wiki-links/index.md")
        self.peep = peep
        let window = peep.waitForWindow(titled: "Wiki Index")
        peep.waitForRenderedText("Go to", in: window)

        // No href, so not exposed as a link: it's text.
        XCTAssertFalse(peep.link("the missing page", in: window).exists)
        let missing = peep.renderedText("the missing page", in: window)
        XCTAssertTrue(missing.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        missing.click()

        // Nothing opens, nothing navigates, and no status says a link was followed or blocked.
        XCTAssertFalse(peep.app.windows["Wiki Target"].waitForExistence(timeout: 1))
        XCTAssertEqual(peep.app.windows.count, 1)
        XCTAssertTrue(peep.renderedText("Go to", in: window).exists)
        XCTAssertFalse(peep.linkStatus(in: window).exists)
    }

    func testSettingsTurnsWikiLinksOn() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "wiki-links/settings.md")
        self.peep = peep
        let window = peep.waitForWindow(titled: "Wiki Settings")
        peep.waitForRenderedText("[[Target Page|the settings target]]", in: window)

        peep.openSettings()
        peep.showSettingsPane("Markdown")
        let toggle = peep.settingsWindow.checkBoxes["settings-preprocessor-wikiLinks"]
        XCTAssertTrue(toggle.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        XCTAssertEqual(toggle.value as? Int, 0, "off by default")
        toggle.click()

        let link = peep.link("the settings target", in: window)
        XCTAssertTrue(link.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "re-rendered with wiki links")
        XCTAssertFalse(peep.renderedText("[[Target Page", in: window).exists)
    }
}
