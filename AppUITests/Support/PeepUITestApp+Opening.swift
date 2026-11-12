import XCTest

extension PeepUITestApp {
    /// Launches Peep opening several fixtures, in order (`-PeepUITestOpen` as a property-list
    /// array).
    @discardableResult
    static func launch(openingFixtures names: [String], restoresState: Bool = false) throws -> PeepUITestApp {
        let paths = try names.map { try Fixtures.url(named: $0).path(percentEncoded: false) }
        return launch(arguments: ["-PeepUITestOpen", propertyListArray(paths)], restoresState: restoresState)
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

    /// Waits until Peep has exactly `count` windows.
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

extension PeepUITestApp {
    /// In the open Open panel, goes to `file`'s folder (Go to Folder, Shift-Cmd-G), selects
    /// `file` in the list, and clicks Open. Fails if Open stays disabled: typing a file's path
    /// into Go to Folder would open even a greyed-out file, so the file is clicked instead.
    func chooseInOpenPanel(
        _ file: URL, file sourceFile: StaticString = #filePath, line: UInt = #line
    ) {
        let panel = openPanel
        app.typeKey("g", modifierFlags: [.command, .shift])
        let field = panel.descendants(matching: .textField).firstMatch
        XCTAssertTrue(
            field.waitForExistence(timeout: Self.defaultTimeout), "Go to Folder field", file: sourceFile, line: line)
        field.typeText(file.deletingLastPathComponent().path(percentEncoded: false) + "\n")
        // List view: in column view (the default on CI's macOS 26 runners) the file's row can
        // sit outside the visible columns, with no hit point.
        app.typeKey("2", modifierFlags: .command)
        let item = panel.descendants(matching: .textField).matching(
            NSPredicate(format: "value == %@", file.lastPathComponent)
        ).firstMatch
        XCTAssertTrue(
            item.waitForExistence(timeout: Self.defaultTimeout), "\(file.lastPathComponent) in the panel",
            file: sourceFile, line: line)
        if item.isHittable {
            item.click()
        } else {
            // Type-select in the file list: a greyed-out file can't be selected this way either.
            app.typeText(file.lastPathComponent)
        }
        let open = panel.buttons["Open"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: open)
        XCTAssertEqual(
            XCTWaiter().wait(for: [enabled], timeout: 3), .completed,
            "Open is enabled for \(file.lastPathComponent)", file: sourceFile, line: line)
        open.click()
    }
}
