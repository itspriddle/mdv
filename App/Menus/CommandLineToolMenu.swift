import AppKit

/// App menu > Install Command Line Tool… (#70). One item whose title follows the current state
/// (Install, Repair, or Uninstall; `AppDelegate.validateMenuItem(_:)` sets it from
/// `CommandLineToolController.currentAction()`), handled by
/// `AppDelegate.installCommandLineTool(_:)`.
enum CommandLineToolMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        let item = NSMenuItem(
            CommandLineToolController.Action.install(preferred: nil).menuTitle,
            action: #selector(AppDelegate.installCommandLineTool(_:)))
        item.identifier = NSUserInterfaceItemIdentifier("command-line-tool")
        menu.addGroup([item], to: .app)
    }
}
