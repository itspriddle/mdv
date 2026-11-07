import XCTest

extension MdvUITestApp {
    /// Chooses View > Theme > `title` (#34).
    func chooseTheme(_ title: String) {
        let view = app.menuBars.menuBarItems["View"]
        view.click()
        let submenu = view.menuItems["Theme"]
        submenu.hover()
        submenu.menuItems[title].click()
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
