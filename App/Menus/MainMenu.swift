import AppKit

/// Builds the app's main menu in code: the standard macOS menus plus groups that features
/// contribute (`MenuContribution`). There is no nib or storyboard.
@MainActor
final class MainMenu {
    /// Features that add menu items, in order. Each feature adds one line here.
    static let contributions: [any MenuContribution.Type] = [DefaultViewerMenu.self, OutlineMenu.self]

    /// The top-level menus features can add to.
    enum Menu: CaseIterable {
        /// Groups go after About (e.g. app-wide commands, until Settings exists).
        case app
        /// Groups go after Open, Open Recent, and Close (e.g. Print).
        case file
        /// Groups go after Copy and Select All (e.g. Find, Copy as HTML).
        case edit
        /// Groups go before Enter Full Screen (e.g. the outline, zoom).
        case view
        /// Groups go before Bring All to Front.
        case window
    }

    private var groups: [Menu: [[NSMenuItem]]] = [:]

    private init() {}

    /// Adds `items` to `menu` as one group, separated from its neighbors.
    func addGroup(_ items: [NSMenuItem], to menu: Menu) {
        groups[menu, default: []].append(items)
    }

    /// Builds the main menu and installs it in `NSApp`, registering the Services, Window, and
    /// Help menus so AppKit maintains them.
    static func install() {
        let mainMenu = build()
        NSApp.mainMenu = mainMenu
        NSApp.servicesMenu = mainMenu.items.first?.submenu?.item(withTitle: "Services")?.submenu
        NSApp.windowsMenu = mainMenu.item(withTitle: "Window")?.submenu
        NSApp.helpMenu = mainMenu.item(withTitle: "Help")?.submenu
    }

    /// The main menu with `contributions` applied.
    static func build(contributions: [any MenuContribution.Type] = contributions) -> NSMenu {
        let builder = MainMenu()
        for contribution in contributions {
            contribution.contribute(to: builder)
        }
        return builder.assemble()
    }

    private func assemble() -> NSMenu {
        let mainMenu = NSMenu(title: "Main Menu")
        for submenu in [appMenu(), fileMenu(), editMenu(), viewMenu(), windowMenu(), NSMenu(title: "Help")] {
            mainMenu.addItem(NSMenuItem(submenu.title, submenu: submenu))
        }
        return mainMenu
    }

    private func appMenu() -> NSMenu {
        let appName = ProcessInfo.processInfo.processName
        return menu(
            appName,
            [
                [NSMenuItem("About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)))]
            ] + groups(for: .app) + [
                [NSMenuItem("Services", submenu: NSMenu(title: "Services"))],
                [
                    NSMenuItem("Hide \(appName)", action: #selector(NSApplication.hide(_:)), key: "h"),
                    NSMenuItem(
                        "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h",
                        modifiers: [.command, .option]),
                    NSMenuItem("Show All", action: #selector(NSApplication.unhideAllApplications(_:))),
                ],
                [NSMenuItem("Quit \(appName)", action: #selector(NSApplication.terminate(_:)), key: "q")],
            ])
    }

    private func fileMenu() -> NSMenu {
        // NSDocumentController finds and maintains Open Recent by its Clear Menu item.
        let openRecent = NSMenu(title: "Open Recent")
        openRecent.addItem(NSMenuItem("Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:))))
        return menu(
            "File",
            [
                [
                    NSMenuItem("Open…", action: #selector(NSDocumentController.openDocument(_:)), key: "o"),
                    NSMenuItem("Open Recent", submenu: openRecent),
                ],
                [NSMenuItem("Close", action: #selector(NSWindow.performClose(_:)), key: "w")],
            ] + groups(for: .file))
    }

    private func editMenu() -> NSMenu {
        menu(
            "Edit",
            [
                [
                    NSMenuItem("Copy", action: #selector(NSText.copy(_:)), key: "c"),
                    NSMenuItem("Select All", action: #selector(NSText.selectAll(_:)), key: "a"),
                ]
            ] + groups(for: .edit))
    }

    private func viewMenu() -> NSMenu {
        menu(
            "View",
            groups(for: .view) + [
                [
                    NSMenuItem(
                        "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), key: "f",
                        modifiers: [.command, .control])
                ]
            ])
    }

    private func windowMenu() -> NSMenu {
        menu(
            "Window",
            [
                [
                    NSMenuItem("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m"),
                    NSMenuItem("Zoom", action: #selector(NSWindow.performZoom(_:))),
                ]
            ] + groups(for: .window) + [
                [NSMenuItem("Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)))]
            ])
    }

    private func groups(for menu: Menu) -> [[NSMenuItem]] {
        groups[menu] ?? []
    }

    /// A menu of item groups with separators between them.
    private func menu(_ title: String, _ groups: [[NSMenuItem]]) -> NSMenu {
        let menu = NSMenu(title: title)
        for (index, group) in groups.enumerated() {
            if index > 0 {
                menu.addItem(.separator())
            }
            group.forEach(menu.addItem)
        }
        return menu
    }
}
