import Foundation

/// Whether new document windows open pinned (on top of other apps' windows): Settings > General.
/// Off until the reader turns it on.
///
/// Each window's own pin (`DocumentWindowController.isPinned`) starts from this and is the value
/// window restoration keeps. Unlike the outline and status bar, pinning a window never changes
/// this default.
struct WindowPinPreference {
    /// The `UserDefaults` key.
    static let key = "PinNewWindows"

    let defaults: UserDefaults
    /// UI tests never write the reader's preference.
    let isPersistent: Bool

    init(defaults: UserDefaults = .standard, isPersistent: Bool = !UITestHooks.isUITesting) {
        self.defaults = defaults
        self.isPersistent = isPersistent
    }

    var pinsNewWindows: Bool {
        get { defaults.bool(forKey: Self.key) }
        nonmutating set {
            guard isPersistent else {
                return
            }
            defaults.set(newValue, forKey: Self.key)
        }
    }
}
