import AppKit

/// "Make mdv the Default Markdown Viewer" in the app menu, until a Settings window exists (M3).
/// `AppDelegate` forwards the action to `DefaultViewerOfferController`, which checks the item
/// and disables it while mdv is already the default.
enum DefaultViewerMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        menu.addGroup(
            [
                NSMenuItem(
                    "Make mdv the Default Markdown Viewer",
                    action: #selector(AppDelegate.makeDefaultMarkdownViewer(_:)))
            ], to: .app)
    }
}
