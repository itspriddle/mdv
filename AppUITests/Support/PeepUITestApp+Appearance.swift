import AppKit
import XCTest

extension PeepUITestApp {
    /// Chooses `title` (System, Light, Dark) in View > Appearance.
    func chooseAppearanceInMenu(_ title: String) {
        let view = app.menuBars.menuBarItems["View"]
        view.click()
        let submenu = view.menuItems["Appearance"]
        submenu.hover()
        submenu.menuItems[title].click()
    }

    /// Waits until `page` (a web view container) is dark or light, read from a screenshot of
    /// its blank bottom-right corner.
    func waitForPage(
        _ page: XCUIElement, isDark: Bool, file: StaticString = #filePath, line: UInt = #line
    ) {
        let turned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in Self.isDark(page) == isDark }, object: nil)
        XCTAssertEqual(
            XCTWaiter.wait(for: [turned], timeout: Self.defaultTimeout), .completed,
            "the page is \(isDark ? "dark" : "light")", file: file, line: line)
    }

    private static func isDark(_ page: XCUIElement) -> Bool? {
        let image = page.screenshot().image
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let color = rep.colorAt(x: rep.pixelsWide - 24, y: rep.pixelsHigh - 24)?.usingColorSpace(.sRGB) else {
            return nil
        }
        return color.brightnessComponent < 0.5
    }
}
