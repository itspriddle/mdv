import Foundation
import PeepCore

/// The content width new document windows start with (#37, #47), persisted in `UserDefaults`.
/// Only Settings sets it; each window then keeps its own preset
/// (`DocumentWindowController.contentWidth`), which View > Content Width changes and window
/// restoration keeps.
@MainActor
final class ContentWidthSettings {
    /// The app's settings. UI tests get an in-memory width that starts at the theme default.
    static let shared = ContentWidthSettings()

    /// Posted (object: the settings) after `defaultWidth` changes.
    static let didChangeNotification = Notification.Name("PeepContentWidthSettingsDidChange")

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

    /// The preset new windows start with. A stored value that isn't one (preferences are untrusted input) reads as
    /// the default.
    var defaultWidth: ContentWidth {
        get {
            guard isPersistent else {
                return memoryWidth
            }
            return defaults.string(forKey: Self.key).flatMap(ContentWidth.init(rawValue:)) ?? .default
        }
        set {
            guard newValue != defaultWidth else {
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
}
