import Foundation
import MdvCore

/// The app-wide content width (#37): one preset for every document window, persisted in
/// `UserDefaults`. View > Content Width changes it, and every window follows the change live
/// (`DocumentWindowController+ContentWidth`). There is no per-window override.
@MainActor
final class ContentWidthSettings {
    /// The app's settings. UI tests get an in-memory width that starts at the theme default.
    static let shared = ContentWidthSettings()

    /// Posted (object: the settings) after `width` changes.
    static let didChangeNotification = Notification.Name("MdvContentWidthSettingsDidChange")

    /// The `UserDefaults` key: a `ContentWidth` raw value, absent at the default.
    static let key = "ContentWidth"

    private let defaults: UserDefaults
    /// UI tests never read or write the reader's preference.
    private let isPersistent: Bool
    private var memoryWidth = ContentWidth.default

    init(defaults: UserDefaults = .standard, isPersistent: Bool = !UITestHooks.isUITesting) {
        self.defaults = defaults
        self.isPersistent = isPersistent
    }

    /// The preset. A stored value that isn't one (preferences are untrusted input) reads as
    /// the default.
    var width: ContentWidth {
        get {
            guard isPersistent else {
                return memoryWidth
            }
            return defaults.string(forKey: Self.key).flatMap(ContentWidth.init(rawValue:)) ?? .default
        }
        set {
            guard newValue != width else {
                return
            }
            if isPersistent {
                if newValue == .default {
                    defaults.removeObject(forKey: Self.key)
                } else {
                    defaults.set(newValue.rawValue, forKey: Self.key)
                }
            } else {
                memoryWidth = newValue
            }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    /// The page's user layer for the current settings.
    var userStyle: UserStyle {
        UserStyle(contentWidth: width)
    }
}
