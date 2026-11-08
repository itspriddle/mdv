import XCTest

/// The custom preprocessor (#57), configured with the Debug-only `-MdvUITestPreprocessor` hook
/// so tests never depend on the reader's settings: its output renders, a failing script shows
/// the bar (with stderr behind Show Details) instead of an alert, and turning it back on in
/// Settings > Markdown needs the warning.
@MainActor
final class CustomPreprocessorUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    private func launch(script name: String) throws -> MdvUITestApp {
        let mdv = try MdvUITestApp.launch(
            openingFixture: "preprocessor.md", arguments: try MdvUITestApp.preprocessorArguments(fixture: name))
        self.mdv = mdv
        return mdv
    }

    func testPreprocessorOutputRenders() throws {
        let mdv = try launch(script: "upcase.sh")
        let window = mdv.waitForWindow(titled: "PREPROCESSOR FIXTURE")
        mdv.waitForRenderedText("PROCESSED BY THE SCRIPT.", in: window)
        XCTAssertFalse(mdv.preprocessorFailureBar(in: window).exists)
    }

    func testFailingScriptShowsBar() throws {
        let mdv = try launch(script: "fail.sh")
        // The document renders without the preprocessor.
        let window = mdv.waitForWindow(titled: "PREPROCESSOR FIXTURE")
        mdv.waitForRenderedText("Processed by the script.", in: window)

        let bar = mdv.preprocessorFailureBar(in: window)
        XCTAssertTrue(bar.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "failure bar")
        let message = bar.descendants(matching: .any)["preprocessor-failure-message"].firstMatch
        XCTAssertTrue(message.displayedText.contains("exited with status 3"), message.displayedText)
        XCTAssertEqual(mdv.app.dialogs.count, 0, "no alert")
        XCTAssertEqual(window.sheets.count, 0, "no sheet")

        let details = bar.descendants(matching: .any)["preprocessor-failure-details"].firstMatch
        XCTAssertFalse(details.exists)
        bar.buttons["preprocessor-failure-details-button"].click()
        XCTAssertTrue(details.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "stderr details")
        XCTAssertTrue(details.displayedText.contains("line 3: boom"), details.displayedText)
    }

    func testTurningOnAgainNeedsTheWarning() throws {
        let mdv = try launch(script: "upcase.sh")
        let window = mdv.waitForWindow(titled: "PREPROCESSOR FIXTURE")
        mdv.waitForRenderedText("PROCESSED BY THE SCRIPT.", in: window)

        let settings = mdv.openSettings()
        mdv.showSettingsPane("Markdown")
        let toggle = settings.checkBoxes["settings-custom-preprocessor"]
        XCTAssertTrue(toggle.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "toggle")
        XCTAssertEqual(toggle.value as? Int, 1)
        let path = settings.descendants(matching: .any)["settings-custom-preprocessor-path"].firstMatch
        XCTAssertTrue(path.displayedText.hasSuffix("/upcase.sh"), path.displayedText)

        // Off: open windows render without it, in place.
        toggle.click()
        mdv.waitForRenderedText("Processed by the script.", in: window)

        // On: the warning first; Cancel keeps it off.
        toggle.click()
        let turnOn = mdv.app.buttons["Turn On"].firstMatch
        XCTAssertTrue(turnOn.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "the warning")
        mdv.app.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(turnOn.waitForNonExistence(timeout: MdvUITestApp.defaultTimeout))
        XCTAssertEqual(toggle.value as? Int, 0)

        toggle.click()
        XCTAssertTrue(turnOn.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "the warning")
        turnOn.click()
        XCTAssertEqual(toggle.value as? Int, 1)
        mdv.waitForRenderedText("PROCESSED BY THE SCRIPT.", in: window)
    }
}
