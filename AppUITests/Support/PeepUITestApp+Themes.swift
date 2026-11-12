import XCTest

extension PeepUITestApp {
    /// Chooses View > Theme > `title` (#34).
    func chooseTheme(_ title: String) {
        chooseThemeMenuItem(title)
    }

    /// Chooses View > Theme > Document's Theme (#54).
    ///
    /// By its identifier (the action), not its title: validation retitles it "Document's Theme
    /// (Serif)" only while the menu is open, and its accessibility title stays "Document's
    /// Theme", so a title query failed on CI when XCUITest looked the item up again after the
    /// click, once the menu had closed (#59).
    func chooseDocumentTheme() {
        chooseThemeMenuItem("useDocumentTheme:")
    }

    private func chooseThemeMenuItem(_ titleOrIdentifier: String) {
        let view = app.menuBars.menuBarItems["View"]
        view.click()
        let submenu = view.menuItems["Theme"]
        submenu.hover()
        submenu.menuItems[titleOrIdentifier].click()
    }

    /// Whether View > Theme lists `title` (#35): opens the menu, looks, and closes it.
    func themeMenuLists(_ title: String) -> Bool {
        let view = app.menuBars.menuBarItems["View"]
        view.click()
        let submenu = view.menuItems["Theme"]
        submenu.hover()
        let exists = submenu.menuItems[title].waitForExistence(timeout: 2)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        return exists
    }

    /// Waits until View > Theme lists `title`, reopening the menu (it is rebuilt each time it
    /// opens) until it does or `timeout` passes.
    func waitForThemeMenuItem(_ title: String, timeout: TimeInterval = defaultTimeout) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if themeMenuLists(title) {
                return true
            }
        }
        return false
    }

    /// A temporary custom themes folder (#35) for `-PeepUITestThemesFolder`; the caller removes it.
    static func makeThemesFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-ui-themes-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The launch arguments that make the app read custom themes from `folder`.
    static func themesFolderArguments(_ folder: URL) -> [String] {
        ["-PeepUITestThemesFolder", folder.path(percentEncoded: false)]
    }

    /// The topmost text in `window`'s web view whose string starts with `prefix` and whose top
    /// is inside the visible part of the page (below the top of the `WKWebView`).
    func firstVisibleText(startingWith prefix: String, in window: XCUIElement) -> XCUIElement? {
        let top = webViewContainer(in: window).frame.minY
        let texts = webView(in: window).staticTexts.matching(
            NSPredicate(format: "CAST(value, 'NSString') BEGINSWITH %@ OR label BEGINSWITH %@", prefix, prefix))
        return texts.allElementsBoundByIndex.first { $0.frame.minY >= top }
    }
}
