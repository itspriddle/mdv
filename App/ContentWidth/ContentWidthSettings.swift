import Foundation
import PeepCore

/// The content width new document windows start with (#37, #47), persisted in `UserDefaults`.
/// Only Settings sets it; each window then keeps its own preset
/// (`DocumentWindowController.contentWidth`), which View > Content Width changes and window
/// restoration keeps.
///
/// It also holds the custom width (a `CustomContentWidth`, off by default): one px width for
/// every window that, while on, wins over each window's preset. Open windows follow it live.
@MainActor
final class ContentWidthSettings {
    /// The app's settings. UI tests get an in-memory width that starts at the theme default.
    static let shared = ContentWidthSettings()

    /// Posted (object: the settings) after `defaultWidth` or the custom width changes.
    static let didChangeNotification = Notification.Name("PeepContentWidthSettingsDidChange")

    /// The `UserDefaults` key: a `ContentWidth` raw value, absent at the default.
    static let key = "ContentWidth"
    /// The `UserDefaults` key for whether the custom width is on: a Bool, absent when off.
    static let customEnabledKey = "CustomContentWidthEnabled"
    /// The `UserDefaults` key for the custom width in px: an Int, absent at the default.
    static let customPointsKey = "CustomContentWidth"

    private let defaults: UserDefaults
    /// UI tests never read or write the reader's preference.
    private let isPersistent: Bool
    private var memoryWidth = ContentWidth.default
    private var memoryCustomEnabled = false
    private var memoryCustomPoints = CustomContentWidth.defaultPoints

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

    /// Whether the custom width overrides every window's preset.
    var isCustomWidthEnabled: Bool {
        get {
            guard isPersistent else {
                return memoryCustomEnabled
            }
            return defaults.object(forKey: Self.customEnabledKey) as? Bool ?? false
        }
        set {
            guard newValue != isCustomWidthEnabled else {
                return
            }
            if isPersistent {
                if newValue {
                    defaults.set(true, forKey: Self.customEnabledKey)
                } else {
                    defaults.removeObject(forKey: Self.customEnabledKey)
                }
            } else {
                memoryCustomEnabled = newValue
            }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    /// The custom width in px, kept while the custom width is off. A stored value that isn't an
    /// in-range Int reads as the default; a new value is clamped to `CustomContentWidth.range`.
    var customWidthPoints: Int {
        get {
            guard isPersistent else {
                return memoryCustomPoints
            }
            guard let points = defaults.object(forKey: Self.customPointsKey) as? Int,
                CustomContentWidth.range.contains(points)
            else {
                return CustomContentWidth.defaultPoints
            }
            return points
        }
        set {
            let range = CustomContentWidth.range
            let points = min(max(newValue, range.lowerBound), range.upperBound)
            guard points != customWidthPoints else {
                return
            }
            if isPersistent {
                if points == CustomContentWidth.defaultPoints {
                    defaults.removeObject(forKey: Self.customPointsKey)
                } else {
                    defaults.set(points, forKey: Self.customPointsKey)
                }
            } else {
                memoryCustomPoints = points
            }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    /// The width that overrides every window's preset, or nil while the custom width is off.
    var customWidth: CustomContentWidth? {
        isCustomWidthEnabled ? CustomContentWidth(points: customWidthPoints) : nil
    }
}
