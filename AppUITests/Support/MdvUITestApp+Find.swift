import XCTest

extension MdvUITestApp {
    /// The find bar's search field in `window` (`FindField` in the app).
    func findField(in window: XCUIElement? = nil) -> XCUIElement {
        (window ?? frontWindow).searchFields["find-field"].firstMatch
    }

    /// The find bar's match count ("2 of 3", "Not found").
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
            XCTFail("find status is \"\(status.label)\", expected \"\(text)\"", file: file, line: line)
        }
    }
}
