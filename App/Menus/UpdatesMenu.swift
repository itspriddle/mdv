import AppKit

/// App menu > Check for Updates… (#81), right after About, handled by
/// `AppDelegate.checkForUpdates(_:)` and enabled by `AppDelegate.validateMenuItem(_:)` while the
/// updater can check (never in builds whose updater is inactive, `SoftwareUpdates`).
enum UpdatesMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        let item = NSMenuItem("Check for Updates…", action: #selector(AppDelegate.checkForUpdates(_:)))
        item.identifier = NSUserInterfaceItemIdentifier("check-for-updates")
        menu.addGroup([item], to: .app)
    }
}
