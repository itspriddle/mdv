import XCTest

extension MdvUITestApp {
    /// A temporary folder for `-MdvUITestCommandLineToolFolder` (#70); the caller removes it.
    static func makeCommandLineToolFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "mdv-ui-bin-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The launch arguments that make App menu > Install Command Line Tool… use `folder`.
    static func commandLineToolFolderArguments(_ folder: URL) -> [String] {
        ["-MdvUITestCommandLineToolFolder", folder.path(percentEncoded: false)]
    }

    /// Opens the App menu and clicks the item titled `title`, failing if it isn't there.
    func clickAppMenuItem(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let appMenu = app.menuBars.menuBarItems.element(boundBy: 1)
        appMenu.click()
        let item = appMenu.menuItems[title]
        if !item.waitForExistence(timeout: Self.defaultTimeout) {
            attachAccessibilityTree()
            XCTFail("No \(title) in the App menu", file: file, line: line)
            return
        }
        item.click()
    }

    /// Waits for an alert button titled `title` and clicks it.
    func clickAlertButton(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.dialogs.buttons[title].firstMatch
        if !button.waitForExistence(timeout: Self.defaultTimeout) {
            attachAccessibilityTree()
            XCTFail("No alert button \(title)", file: file, line: line)
            return
        }
        button.click()
    }

    /// Waits for an alert containing `text` (its message or informative text).
    func waitForAlertText(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", text, text)
        let element = app.dialogs.staticTexts.matching(predicate).firstMatch
        if !element.waitForExistence(timeout: Self.defaultTimeout) {
            attachAccessibilityTree()
            XCTFail("No alert with \(text)", file: file, line: line)
        }
    }
}
