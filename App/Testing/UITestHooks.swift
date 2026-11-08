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
///   Links that would leave the app (browser, Finder) are shown in the link status overlay
///   instead (`opensLinksOutsideApp`).
/// - `-MdvUITestOpen <path>`: open the document at an absolute path once launched, without the
///   Open panel. A property-list array (`-MdvUITestOpen '("/a.md", "/b.md")'`) opens several,
///   in order.
/// - `-MdvUITestThemesFolder <path>`: read custom themes (#35) from this absolute path
///   instead of `~/Library/Application Support/mdv/Themes`. Without it a UI-test launch loads
///   no custom themes, so tests never read or create the reader's folder.
/// - `-MdvUITestPreprocessor <path>`: start with the custom preprocessor (#57) on, running the
///   executable at this absolute path with no arguments (`CustomPreprocessorSettings.shared`,
///   in memory). Without it a UI-test launch has no preprocessor, whatever the reader set.
///
/// UI-test launches (and hosted unit tests) never add to Open Recent (`DocumentController`).
enum UITestHooks {
    #if DEBUG
        /// Launch argument (a `UserDefaults` key) that marks a UI-test launch.
        static let uiTestingKey = "MdvUITesting"
        /// Launch argument (a `UserDefaults` key) with an absolute path to open at launch.
        static let openKey = "MdvUITestOpen"
        /// Launch argument (a `UserDefaults` key) with an absolute path to the custom themes folder.
        static let themesFolderKey = "MdvUITestThemesFolder"
        /// Launch argument (a `UserDefaults` key) with an absolute path to a custom preprocessor.
        static let preprocessorKey = "MdvUITestPreprocessor"
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

    /// Whether links may leave mdv: open in the browser or other apps, or reveal in Finder.
    /// UI tests turn this off; the window shows what would have opened instead (#19).
    static var opensLinksOutsideApp: Bool {
        !isUITesting
    }

    /// The documents a UI test asked to open at launch, in order. Always empty in Release builds.
    static var documentsToOpen: [URL] {
        #if DEBUG
            guard isUITesting else {
                return []
            }
            let defaults = UserDefaults.standard
            let paths = defaults.stringArray(forKey: openKey) ?? defaults.string(forKey: openKey).map { [$0] } ?? []
            return paths.filter { $0.hasPrefix("/") }.map { URL(filePath: $0) }
        #else
            []
        #endif
    }

    /// The custom themes folder a UI test asked for, or nil (the real folder outside UI tests,
    /// no custom themes in them; see `CustomThemeLibrary.folderURL`). Always nil in Release.
    static var themesFolder: URL? {
        #if DEBUG
            guard isUITesting, let path = UserDefaults.standard.string(forKey: themesFolderKey), path.hasPrefix("/")
            else {
                return nil
            }
            return URL(filePath: path, directoryHint: .isDirectory)
        #else
            nil
        #endif
    }

    /// The custom preprocessor executable a UI test asked for, or nil. Always nil in Release.
    static var preprocessorExecutable: String? {
        #if DEBUG
            guard isUITesting, let path = UserDefaults.standard.string(forKey: preprocessorKey), path.hasPrefix("/")
            else {
                return nil
            }
            return path
        #else
            nil
        #endif
    }
}
