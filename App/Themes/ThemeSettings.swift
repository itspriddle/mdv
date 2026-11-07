import Foundation
import MdvCore

/// The app's themes (#34): the registry every window resolves its theme in, and the theme new
/// windows start with.
///
/// Each window keeps its own theme (`DocumentWindowController.themeID`, restorable state). This
/// holds what they share:
/// - `registry`: the themes the picker lists. Custom themes (#35) replace it with
///   `ThemeRegistry.bundled.adding(customThemes)`; every window then resolves its theme again
///   and swaps in a changed or removed one in place.
/// - `defaultThemeID`: the theme for new windows, persisted. Until Settings (#36) sets it, the
///   last theme picked in any window.
@MainActor
final class ThemeSettings {
    /// The app's settings. UI tests keep the default theme in memory.
    static let shared = ThemeSettings()

    /// Posted (object: the settings) after `registry` or `defaultThemeID` changes.
    static let didChangeNotification = Notification.Name("MdvThemeSettingsDidChange")

    /// The `UserDefaults` key: the default theme's id (a `String`), absent for the registry's
    /// own default.
    static let defaultThemeKey = "DefaultTheme"

    private let defaults: UserDefaults
    /// UI tests never read or write the reader's preference.
    private let isPersistent: Bool
    private var memoryDefaultThemeID: String?

    /// The themes windows can show. Setting it tells every window to resolve its theme again.
    var registry: ThemeRegistry {
        didSet {
            if registry != oldValue {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
            }
        }
    }

    init(
        registry: ThemeRegistry = .bundled,
        defaults: UserDefaults = .standard,
        isPersistent: Bool = !UITestHooks.isUITesting
    ) {
        self.registry = registry
        self.defaults = defaults
        self.isPersistent = isPersistent
    }

    /// The id of the theme new windows use. May name a theme that isn't registered (a deleted
    /// custom theme); `defaultTheme` then falls back to the registry's default.
    var defaultThemeID: String? {
        get {
            isPersistent ? defaults.string(forKey: Self.defaultThemeKey) : memoryDefaultThemeID
        }
        set {
            guard newValue != defaultThemeID else {
                return
            }
            if isPersistent {
                defaults.set(newValue, forKey: Self.defaultThemeKey)
            } else {
                memoryDefaultThemeID = newValue
            }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    /// The theme new windows start with.
    var defaultTheme: Theme {
        registry.theme(id: defaultThemeID)
    }
}
