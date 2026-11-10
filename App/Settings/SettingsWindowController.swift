import AppKit
import SwiftUI

/// The Settings window (#36): App menu > Settings… (Command-comma, `SettingsMenu`).
///
/// One reusable window for the app's lifetime (`AppDelegate.showSettings(_:)`). The app
/// lifecycle is AppKit, so there is no SwiftUI `Settings` scene: an `NSTabViewController` in
/// toolbar style holds one pane per tab, each a SwiftUI form in an `NSHostingController`. A new
/// pane is one more `pane(...)` in `init`. The window remembers its position
/// (`frameAutosaveName`, not under UI tests) and isn't restored at launch.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// The window's accessibility identifier, for UI tests.
    static let windowIdentifier = NSUserInterfaceItemIdentifier("settings-window")
    static let frameAutosaveName = "MdvSettings"

    let model: SettingsModel

    init(model: SettingsModel, savesFrame: Bool = !UITestHooks.isUITesting) {
        self.model = model
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(
            Self.pane("General", symbol: "gearshape", identifier: "general", GeneralSettingsView(model: model)))
        tabs.addTabViewItem(
            Self.pane("Markdown", symbol: "doc.text", identifier: "markdown", MarkdownSettingsView(model: model)))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.identifier = Self.windowIdentifier
        window.isRestorable = false
        window.collectionBehavior.insert(.fullScreenNone)
        super.init(window: window)
        window.delegate = self
        if !savesFrame || !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        if savesFrame {
            window.setFrameAutosaveName(Self.frameAutosaveName)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController is created in code")
    }

    /// A tab whose content is `view`, sized to fit it.
    private static func pane(
        _ label: String, symbol: String, identifier: String, _ view: some View
    ) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        // The tab view controller shows the selected pane's title as the window's.
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.identifier = identifier
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    /// Shows the window in front, with current values.
    func show() {
        model.refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: NSWindowDelegate

    /// The outline preference and the default viewer post no change notifications; read them
    /// again whenever the reader comes back to the window.
    func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
    }
}
