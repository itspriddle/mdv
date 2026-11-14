import XCTest

extension PeepUITestApp {
    /// The word count in `window`'s status bar (`WordCountItem` in the app).
    func wordCount(in window: XCUIElement? = nil) -> XCUIElement {
        (window ?? frontWindow).staticTexts["word-count"].firstMatch
    }

    /// The outline toggle in `window`'s status bar (`OutlineToggleItem` in the app).
    func outlineToggle(in window: XCUIElement? = nil) -> XCUIElement {
        (window ?? frontWindow).buttons["outline-toggle"].firstMatch
    }

    /// The pin toggle in `window`'s status bar (`PinToggleItem` in the app); its value is "on"
    /// while the window is pinned.
    func pinToggle(in window: XCUIElement? = nil) -> XCUIElement {
        (window ?? frontWindow).buttons["pin-toggle"].firstMatch
    }
}
