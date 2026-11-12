import AppKit

/// The app's appearance: follow the system, or always light or dark.
enum AppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    /// The appearance to set on the app; nil follows the system.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// The app-wide appearance, persisted in `UserDefaults`. Settings and View > Appearance change
/// it; `AppDelegate` sets it on `NSApp`, so every window (and its web view's
/// `prefers-color-scheme`, and the theme background colors) follows live. Print stays light
/// regardless.
@MainActor
final class AppearanceSettings {
    /// The app's settings. UI tests get an in-memory mode that starts at `.system`.
    static let shared = AppearanceSettings()

    /// Posted (object: the settings) after `mode` changes.
    static let didChangeNotification = Notification.Name("PeepAppearanceSettingsDidChange")

    /// The `UserDefaults` key: an `AppearanceMode` raw value, absent at `.system`.
    static let key = "Appearance"

    private let defaults: UserDefaults
    /// UI tests never read or write the reader's preference.
    private let isPersistent: Bool
    private var memoryMode = AppearanceMode.system

    init(defaults: UserDefaults = .standard, isPersistent: Bool = !UITestHooks.isUITesting) {
        self.defaults = defaults
        self.isPersistent = isPersistent
    }

    /// The mode. A stored value that isn't one (preferences are untrusted input) reads as
    /// `.system`.
    var mode: AppearanceMode {
        get {
            guard isPersistent else {
                return memoryMode
            }
            return defaults.string(forKey: Self.key).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        }
        set {
            guard newValue != mode else {
                return
            }
            if isPersistent {
                if newValue == .system {
                    defaults.removeObject(forKey: Self.key)
                } else {
                    defaults.set(newValue.rawValue, forKey: Self.key)
                }
            } else {
                memoryMode = newValue
            }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    /// Sets the current mode's appearance on `target` (the app, or a window in tests).
    func apply(to target: some NSAppearanceCustomization) {
        target.appearance = mode.appearance
    }
}
