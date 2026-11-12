import XCTest

extension MdvUITestApp {
    /// The outline's accessibility identifier (`OutlineViewController` in the app).
    static let outlineIdentifier = "document-outline"

    /// The outline sidebar in `window`.
    func outline(in window: XCUIElement? = nil) -> XCUIElement {
        (window ?? frontWindow).outlines[Self.outlineIdentifier].firstMatch
    }

    /// The outline row whose cell text is `text`.
    func outlineText(_ text: String, in window: XCUIElement? = nil) -> XCUIElement {
        outline(in: window).staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", text, text))
            .firstMatch
    }
}
