import AppKit
import XCTest

extension PeepUITestApp {
    /// The find bar's search field in `window` (`FindField` in the app).
    func findField(in window: XCUIElement? = nil) -> XCUIElement {
        (window ?? frontWindow).searchFields["find-field"].firstMatch
    }

    /// The find bar's match count ("2 of 3", "Not found"). SwiftUI exposes the text as the
    /// element's value.
    func findStatus(in window: XCUIElement? = nil) -> XCUIElement {
        (window ?? frontWindow).staticTexts["find-status"].firstMatch
    }

    /// Waits until the find status reads `text`.
    func waitForFindStatus(
        _ text: String, in window: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line
    ) {
        let status = findStatus(in: window)
        let predicate = NSPredicate(format: "label == %@ OR value == %@", text, text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
        if XCTWaiter.wait(for: [expectation], timeout: Self.defaultTimeout) != .completed {
            let shown = status.exists ? status.displayedText : "(none)"
            XCTFail("find status is \"\(shown)\", expected \"\(text)\"", file: file, line: line)
        }
    }

    /// Waits until `pasteboard`'s plain text is `text`.
    static func waitForString(
        _ text: String, on pasteboard: NSPasteboard, file: StaticString = #filePath, line: UInt = #line
    ) {
        let matches = NSPredicate { _, _ in pasteboard.string(forType: .string) == text }
        let expectation = XCTNSPredicateExpectation(predicate: matches, object: nil)
        if XCTWaiter.wait(for: [expectation], timeout: defaultTimeout) != .completed {
            let shown = pasteboard.string(forType: .string) ?? "nil"
            XCTFail(
                "pasteboard \(pasteboard.name.rawValue) is \"\(shown)\", expected \"\(text)\"", file: file, line: line)
        }
    }
}
