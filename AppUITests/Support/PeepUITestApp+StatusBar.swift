import XCTest

extension PeepUITestApp {
    /// The word count in `window`'s status bar (`WordCountItem` in the app).
    func wordCount(in window: XCUIElement? = nil) -> XCUIElement {
        (window ?? frontWindow).staticTexts["word-count"].firstMatch
    }
}
