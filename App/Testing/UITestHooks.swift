import Foundation

/// Launch hooks for `AppUITests`, read from the argument domain of `UserDefaults` (launch
/// arguments `-Key value`).
///
/// The hooks exist in Debug builds only. In Release builds every property reports "not testing"
/// and the argument names are not compiled in, so a shipped app ignores them.
///
/// - `-MdvUITesting YES`: the app is driven by a UI test. It skips the Open panel at launch and
///   suppresses first-run prompts. Features that show a first-run prompt (e.g. #23's offer to
///   become the default Markdown viewer) must check `suppressesFirstRunPrompts` before showing it.
/// - `-MdvUITestOpen <path>`: open the document at an absolute path once launched, without the
///   Open panel.
enum UITestHooks {
    #if DEBUG
        /// Launch argument (a `UserDefaults` key) that marks a UI-test launch.
        static let uiTestingKey = "MdvUITesting"
        /// Launch argument (a `UserDefaults` key) with an absolute path to open at launch.
        static let openKey = "MdvUITestOpen"
    #endif

    /// Whether a UI test launched the app. Always `false` in Release builds.
    static var isUITesting: Bool {
        #if DEBUG
            UserDefaults.standard.bool(forKey: uiTestingKey)
        #else
            false
        #endif
    }

    /// Whether first-run prompts (default-handler offer, onboarding) must stay hidden.
    static var suppressesFirstRunPrompts: Bool {
        isUITesting
    }

    /// The document a UI test asked to open at launch, if any. Always `nil` in Release builds.
    static var documentToOpen: URL? {
        #if DEBUG
            guard isUITesting, let path = UserDefaults.standard.string(forKey: openKey), path.hasPrefix("/") else {
                return nil
            }
            return URL(filePath: path)
        #else
            nil
        #endif
    }
}
