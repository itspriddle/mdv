import AppKit

/// The app-wide appearance: Settings > Appearance and View > Appearance (`AppearanceMenu`)
/// change `AppDelegate.appearanceSettings`, and the app follows it. The menu's action lives on
/// the app delegate, so it works with no document window open.
extension AppDelegate {
    /// Sets the appearance on the app now (before any window or web view exists, so the first
    /// paint is right) and again on every change.
    func followAppearanceSettings() {
        appearanceSettings.apply(to: NSApplication.shared)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appearanceSettingsDidChange(_:)),
            name: AppearanceSettings.didChangeNotification, object: appearanceSettings)
    }

    @objc private func appearanceSettingsDidChange(_ notification: Notification) {
        appearanceSettings.apply(to: NSApplication.shared)
    }

    /// View > Appearance > (mode). The item's `representedObject` is the mode's raw value.
    @objc func chooseAppearance(_ sender: Any?) {
        guard let rawValue = (sender as? NSMenuItem)?.representedObject as? String,
            let mode = AppearanceMode(rawValue: rawValue)
        else {
            return
        }
        appearanceSettings.mode = mode
    }

    /// Checks the current mode.
    func validateAppearanceItem(_ menuItem: NSMenuItem) -> Bool {
        let rawValue = menuItem.representedObject as? String
        menuItem.state = rawValue == appearanceSettings.mode.rawValue ? .on : .off
        return true
    }
}
