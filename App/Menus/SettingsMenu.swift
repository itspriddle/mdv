import AppKit

/// App menu > Settings… (Command-comma), which shows the Settings window (#36,
/// `AppDelegate.showSettings(_:)`). "Make mdv the Default Markdown Viewer" moved from this
/// menu into Settings.
enum SettingsMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        menu.addGroup([NSMenuItem("Settings…", action: #selector(AppDelegate.showSettings(_:)), key: ",")], to: .app)
    }
}
