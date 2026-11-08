import XCTest

/// Wiki links (#53) in the running app: a found page opens in mdv when clicked, a missing one
/// does nothing, and Settings > Markdown turns them on for open documents.
@MainActor
final class WikiLinksUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    func testClickingWikiLinkOpensTarget() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "wiki-links/index.md")
        self.mdv = mdv
        let window = mdv.waitForWindow(titled: "Wiki Index")
        mdv.waitForRenderedText("Go to", in: window)

        mdv.link("the wiki target", in: window).click()
        let target = mdv.waitForWindow(titled: "Wiki Target")
        mdv.waitForRenderedText("Target page text.", in: target)
        XCTAssertTrue(mdv.window(titled: "Wiki Index").exists)
    }

    func testMissingWikiLinkDoesNothing() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "wiki-links/index.md")
        self.mdv = mdv
        let window = mdv.waitForWindow(titled: "Wiki Index")
        mdv.waitForRenderedText("Go to", in: window)

        // No href, so not exposed as a link: it's text.
        XCTAssertFalse(mdv.link("the missing page", in: window).exists)
        let missing = mdv.renderedText("the missing page", in: window)
        XCTAssertTrue(missing.waitForExistence(timeout: MdvUITestApp.defaultTimeout))
        missing.click()

        // Nothing opens, nothing navigates, and no status says a link was followed or blocked.
        XCTAssertFalse(mdv.app.windows["Wiki Target"].waitForExistence(timeout: 1))
        XCTAssertEqual(mdv.app.windows.count, 1)
        XCTAssertTrue(mdv.renderedText("Go to", in: window).exists)
        XCTAssertFalse(mdv.linkStatus(in: window).exists)
    }

    func testSettingsTurnsWikiLinksOn() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "wiki-links/settings.md")
        self.mdv = mdv
        let window = mdv.waitForWindow(titled: "Wiki Settings")
        mdv.waitForRenderedText("[[Target Page|the settings target]]", in: window)

        mdv.openSettings()
        mdv.showSettingsPane("Markdown")
        let toggle = mdv.settingsWindow.checkBoxes["settings-preprocessor-wikiLinks"]
        XCTAssertTrue(toggle.waitForExistence(timeout: MdvUITestApp.defaultTimeout))
        XCTAssertEqual(toggle.value as? Int, 0, "off by default")
        toggle.click()

        let link = mdv.link("the settings target", in: window)
        XCTAssertTrue(link.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "re-rendered with wiki links")
        XCTAssertFalse(mdv.renderedText("[[Target Page", in: window).exists)
    }
}
