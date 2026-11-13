import Foundation

/// Whether new document windows show the status bar: the last choice made with View > Show/Hide
/// Status Bar, in any window. Shown until the reader first hides it.
///
/// Each window's own visibility (`DocumentWindowController.isStatusBarVisible`) starts from this
/// and is the value window restoration keeps.
struct StatusBarPreference {
    /// The `UserDefaults` key.
    static let key = "StatusBarVisible"

    let defaults: UserDefaults
    /// UI tests never write the reader's preference.
    let isPersistent: Bool

    init(defaults: UserDefaults = .standard, isPersistent: Bool = !UITestHooks.isUITesting) {
        self.defaults = defaults
        self.isPersistent = isPersistent
    }

    var showsStatusBarInNewWindows: Bool {
        get { defaults.object(forKey: Self.key) as? Bool ?? true }
        nonmutating set {
            guard isPersistent else {
                return
            }
            defaults.set(newValue, forKey: Self.key)
        }
    }
}
