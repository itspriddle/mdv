import Foundation

/// Page zoom levels (`WKWebView.pageZoom`, which reflows text) for View > Zoom In, Zoom Out,
/// and Actual Size. The steps match Safari's.
enum PageZoom {
    /// Every level Zoom In and Zoom Out step through, ascending.
    static let levels: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
    static let actualSize = 1.0

    /// Treats levels this close as equal, so a stored 1.1 doesn't step to 1.1 again.
    private static let tolerance = 0.001

    /// The next level above `level`, or nil at the largest.
    static func larger(than level: Double) -> Double? {
        levels.first { $0 > level + tolerance }
    }

    /// The next level below `level`, or nil at the smallest.
    static func smaller(than level: Double) -> Double? {
        levels.last { $0 < level - tolerance }
    }

    /// `level` if it is usable (finite and within the range of `levels`), else nil. Stored
    /// preferences are untrusted input.
    static func valid(_ level: Double) -> Double? {
        guard level.isFinite, let lowest = levels.first, let highest = levels.last,
            level >= lowest - tolerance, level <= highest + tolerance
        else {
            return nil
        }
        return level
    }

    static func isActualSize(_ level: Double) -> Bool {
        abs(level - actualSize) < tolerance
    }
}

/// The app-wide page zoom: one level for every document window, persisted in `UserDefaults`.
/// Zoom In, Zoom Out, and Actual Size change it, and every window follows the change. Pinch
/// magnification is each window's own override on top of it (`DocumentWindowController+Zoom`).
@MainActor
final class ZoomSettings {
    /// The app's settings. UI tests get an in-memory level that starts at actual size.
    static let shared = ZoomSettings()

    /// Posted (object: the settings) after `level` changes.
    static let didChangeNotification = Notification.Name("MdvZoomSettingsDidChange")

    /// The `UserDefaults` key: a `Double`, absent at actual size.
    static let key = "PageZoom"

    private let defaults: UserDefaults
    /// UI tests never read or write the reader's preference.
    private let isPersistent: Bool
    private var memoryLevel = PageZoom.actualSize

    init(defaults: UserDefaults = .standard, isPersistent: Bool = !UITestHooks.isUITesting) {
        self.defaults = defaults
        self.isPersistent = isPersistent
    }

    var level: Double {
        get {
            guard isPersistent else {
                return memoryLevel
            }
            return PageZoom.valid(defaults.double(forKey: Self.key)) ?? PageZoom.actualSize
        }
        set {
            let level = PageZoom.valid(newValue) ?? PageZoom.actualSize
            guard level != self.level else {
                return
            }
            if isPersistent {
                if PageZoom.isActualSize(level) {
                    defaults.removeObject(forKey: Self.key)
                } else {
                    defaults.set(level, forKey: Self.key)
                }
            } else {
                memoryLevel = level
            }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }
}
