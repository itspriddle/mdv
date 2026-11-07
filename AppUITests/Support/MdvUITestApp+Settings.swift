import XCTest

extension MdvUITestApp {
    /// The Settings window (identifier `settings-window`, set by `SettingsWindowController`).
    var settingsWindow: XCUIElement {
        app.windows["settings-window"]
    }

    /// Opens Settings with Command-comma and waits for its window.
    @discardableResult
    func openSettings(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        app.typeKey(",", modifierFlags: .command)
        let window = settingsWindow
        if !window.waitForExistence(timeout: Self.defaultTimeout) {
            attachAccessibilityTree()
            XCTFail("No Settings window", file: file, line: line)
        }
        return window
    }

    /// Chooses `title` in the Settings pop-up button with `identifier` (e.g.
    /// `settings-default-theme`).
    func chooseSetting(_ title: String, in identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let popUp = settingsWindow.popUpButtons[identifier]
        XCTAssertTrue(popUp.waitForExistence(timeout: Self.defaultTimeout), identifier, file: file, line: line)
        popUp.click()
        let item = popUp.menuItems[title]
        if !item.waitForExistence(timeout: Self.defaultTimeout) {
            attachAccessibilityTree()
            XCTFail("No \(title) in \(identifier)", file: file, line: line)
        }
        item.click()
    }
}
