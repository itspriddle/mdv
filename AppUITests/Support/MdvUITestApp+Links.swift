import XCTest

extension MdvUITestApp {
    /// The link status overlay's accessibility identifier (`LinkStatusView` in the app).
    static let linkStatusIdentifier = "link-status"

    /// The link in the web view of `window` whose text contains `text`.
    func link(_ text: String, in window: XCUIElement? = nil) -> XCUIElement {
        webView(in: window).links.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// The link status overlay in `window`.
    func linkStatus(in window: XCUIElement? = nil) -> XCUIElement {
        (window ?? frontWindow).descendants(matching: .any)[Self.linkStatusIdentifier].firstMatch
    }
}
