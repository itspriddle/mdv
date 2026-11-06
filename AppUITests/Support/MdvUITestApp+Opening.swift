import XCTest

extension MdvUITestApp {
    /// Launches mdv opening several fixtures, in order (`-MdvUITestOpen` as a property-list
    /// array).
    @discardableResult
    static func launch(openingFixtures names: [String], restoresState: Bool = false) throws -> MdvUITestApp {
        let paths = try names.map { try Fixtures.url(named: $0).path(percentEncoded: false) }
        return launch(arguments: ["-MdvUITestOpen", propertyListArray(paths)], restoresState: restoresState)
    }

    /// An old-style property-list array of strings, as the `UserDefaults` argument domain parses.
    static func propertyListArray(_ strings: [String]) -> String {
        let quoted = strings.map { string in
            "\"" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                + "\""
        }
        return "(" + quoted.joined(separator: ", ") + ")"
    }

    /// The tab in `window`'s tab bar titled `title`.
    func tab(titled title: String, in window: XCUIElement) -> XCUIElement {
        window.tabGroups.firstMatch.descendants(matching: .any).matching(
            NSPredicate(format: "title == %@ OR label == %@", title, title)
        )
        .firstMatch
    }

    /// The Open panel. AppKit shows it as a standalone window with the identifier `open-panel`
    /// (not a dialog or a sheet), titled "Open".
    var openPanel: XCUIElement {
        app.windows["open-panel"]
    }

    /// Waits until mdv has exactly `count` windows.
    func waitForWindowCount(
        _ count: Int, timeout: TimeInterval = defaultTimeout, file: StaticString = #filePath, line: UInt = #line
    ) {
        let predicate = NSPredicate { _, _ in self.app.windows.count == count }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        if XCTWaiter().wait(for: [expectation], timeout: timeout) != .completed {
            let titles = app.windows.allElementsBoundByIndex.map(\.title)
            XCTFail("Expected \(count) windows; windows: \(titles)", file: file, line: line)
        }
    }
}
