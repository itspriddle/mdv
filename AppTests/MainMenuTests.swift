import AppKit
import Testing

@testable import MdvApp

@MainActor
@Suite("MainMenu")
struct MainMenuTests {
    /// A stand-in feature with one item in the View menu and one in the File menu.
    enum SampleContribution: MenuContribution {
        static func contribute(to menu: MainMenu) {
            menu.addGroup([NSMenuItem("Sample View Item", action: #selector(NSText.copy(_:)))], to: .view)
            menu.addGroup([NSMenuItem("Sample File Item", action: #selector(NSText.copy(_:)))], to: .file)
        }
    }

    func titles(_ menu: NSMenu?) -> [String] {
        menu?.items.map { $0.isSeparatorItem ? "-" : $0.title } ?? []
    }

    @Test("has the standard menus")
    func standardMenus() {
        let menu = MainMenu.build(contributions: [])
        #expect(titles(menu).dropFirst() == ["File", "Edit", "View", "Window", "Help"])
        #expect(titles(menu.item(withTitle: "File")?.submenu) == ["Open…", "Open Recent", "-", "Close"])
        let openRecent = menu.item(withTitle: "File")?.submenu?.item(withTitle: "Open Recent")?.submenu
        #expect(openRecent?.items.first?.action == #selector(NSDocumentController.clearRecentDocuments(_:)))
    }

    @Test("places contributed groups in their menus")
    func contributions() {
        let menu = MainMenu.build(contributions: [SampleContribution.self])
        #expect(titles(menu.item(withTitle: "View")?.submenu) == ["Sample View Item", "-", "Enter Full Screen"])
        #expect(
            titles(menu.item(withTitle: "File")?.submenu) == [
                "Open…", "Open Recent", "-", "Close", "-", "Sample File Item",
            ])
    }

    @Test("the running app uses the built menu")
    func installed() {
        #expect(NSApp.mainMenu?.item(withTitle: "File") != nil)
        #expect(NSApp.windowsMenu === NSApp.mainMenu?.item(withTitle: "Window")?.submenu)
    }
}
