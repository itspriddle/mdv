import Foundation

/// Whether new document windows show the outline: the last choice made with View > Show/Hide
/// Outline or the status bar button, in any window. Hidden until the reader first shows it.
///
/// Each window's own visibility (`DocumentWindowController.isOutlineVisible`) starts from this
/// and is the value window restoration keeps.
struct OutlinePreference {
    /// The `UserDefaults` key.
    static let key = "OutlineVisible"

    let defaults: UserDefaults
    /// UI tests never write the reader's preference.
    let isPersistent: Bool

    init(defaults: UserDefaults = .standard, isPersistent: Bool = !UITestHooks.isUITesting) {
        self.defaults = defaults
        self.isPersistent = isPersistent
    }

    var showsOutlineInNewWindows: Bool {
        get { defaults.bool(forKey: Self.key) }
        nonmutating set {
            guard isPersistent else {
                return
            }
            defaults.set(newValue, forKey: Self.key)
        }
    }
}
