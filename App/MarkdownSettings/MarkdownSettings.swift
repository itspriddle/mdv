import Foundation
import MdvCore

/// How documents are read (#55, Settings > Markdown), as one value: what a render needs from
/// Settings. Built on the main actor from `MarkdownSettings` and passed to the off-main render,
/// so a render never reads a store; `DocumentContent` keeps the value it was rendered with.
struct MarkdownPreferences: Equatable, Sendable {
    /// The default flavor. A document's frontmatter `mdv.flavor` (#54) still wins: this is only
    /// `RenderOptions.flavor`, which MdvCore's flavor resolution overrides.
    var flavor = Flavor.gfm
    /// Whether frontmatter is hidden or shown as a table before the body.
    var frontmatterDisplay = FrontmatterDisplay.hidden
    /// Opt-in built-in preprocessors (#53's wiki links), independent of the flavor. Only
    /// `MarkdownSettings.optionalPreprocessors` ever appear here.
    var builtInPreprocessors: Set<MarkdownTransform> = []
    /// The custom preprocessor (#57), stage 1 of the pipeline, or `nil` when it's off. Comes
    /// from `CustomPreprocessorSettings`, not this store: `MarkdownDocument.renderPreferences`
    /// fills it in. `apply(to:)` ignores it; `DocumentContent.rendering` runs it.
    var customPreprocessor: CustomPreprocessorPreference?

    /// GFM, frontmatter hidden, no built-in preprocessors: the app before #55, and `mdv --html`.
    static let `default` = MarkdownPreferences()

    /// Applies these preferences to `options`.
    func apply(to options: inout RenderOptions) {
        options.flavor = flavor
        options.frontmatterDisplay = frontmatterDisplay
        options.builtInPreprocessors = builtInPreprocessors
    }
}

/// The reader's Markdown settings (#55), persisted in `UserDefaults`: the default flavor, how
/// frontmatter shows, and which built-in preprocessors are on. Only Settings > Markdown sets
/// them. They apply to every document, open ones included: each `MarkdownDocument` follows
/// `didChangeNotification` and re-renders in place, keeping the reading position (the live
/// reload path).
///
/// Stored values are untrusted input: an unknown flavor id reads as GFM, an unknown frontmatter
/// display as hidden, and preprocessors not in `optionalPreprocessors` are dropped.
@MainActor
final class MarkdownSettings {
    /// The app's settings. UI tests and hosted unit tests keep them in memory, starting at the
    /// defaults, so neither reads nor writes the reader's preferences.
    static let shared = MarkdownSettings(isPersistent: !UITestHooks.isUITesting && !AppDelegate.isHostingUnitTests)

    /// Posted (object: the settings) after any setting changes.
    static let didChangeNotification = Notification.Name("MdvMarkdownSettingsDidChange")

    /// `UserDefaults` keys. Each is absent at its default.
    static let flavorKey = "DefaultFlavor"
    static let frontmatterKey = "FrontmatterDisplay"
    static let preprocessorsKey = "BuiltInPreprocessors"

    /// The built-in preprocessors Settings offers, in the order it lists them: opt-in
    /// `MarkdownTransform`s, never flavor-owned ones (emoji, alerts). Empty until wiki links
    /// (#53) add `.wikiLinks`; Settings > Markdown hides the section while it's empty.
    static let optionalPreprocessors: [MarkdownTransform] = []

    /// The flavors the default-flavor picker lists.
    let registry: FlavorRegistry
    private let defaults: UserDefaults
    /// UI tests never read or write the reader's preference.
    private let isPersistent: Bool
    private var memory = MarkdownPreferences.default

    init(
        registry: FlavorRegistry = .bundled, defaults: UserDefaults = .standard,
        isPersistent: Bool = !UITestHooks.isUITesting
    ) {
        self.registry = registry
        self.defaults = defaults
        self.isPersistent = isPersistent
    }

    /// Everything a render needs, as one value.
    var preferences: MarkdownPreferences {
        MarkdownPreferences(
            flavor: defaultFlavor, frontmatterDisplay: frontmatterDisplay, builtInPreprocessors: builtInPreprocessors)
    }

    /// The default flavor's id, resolved in `registry` (an unknown stored id is the registry's
    /// default, GFM). Setting an id the registry doesn't have is ignored.
    var defaultFlavorID: String {
        get {
            defaultFlavor.id
        }
        set {
            guard registry.contains(id: newValue), newValue != defaultFlavorID else {
                return
            }
            if isPersistent {
                if newValue == registry.defaultFlavor.id {
                    defaults.removeObject(forKey: Self.flavorKey)
                } else {
                    defaults.set(newValue, forKey: Self.flavorKey)
                }
            } else {
                memory.flavor = registry.flavor(id: newValue)
            }
            didChange()
        }
    }

    /// The default flavor documents render with (unless their frontmatter names one, #54).
    var defaultFlavor: Flavor {
        isPersistent ? registry.flavor(id: defaults.string(forKey: Self.flavorKey)) : memory.flavor
    }

    /// Whether frontmatter is hidden or shown as a table.
    var frontmatterDisplay: FrontmatterDisplay {
        get {
            guard isPersistent else {
                return memory.frontmatterDisplay
            }
            return defaults.string(forKey: Self.frontmatterKey).flatMap(FrontmatterDisplay.init(rawValue:)) ?? .hidden
        }
        set {
            guard newValue != frontmatterDisplay else {
                return
            }
            if isPersistent {
                if newValue == .hidden {
                    defaults.removeObject(forKey: Self.frontmatterKey)
                } else {
                    defaults.set(newValue.rawValue, forKey: Self.frontmatterKey)
                }
            } else {
                memory.frontmatterDisplay = newValue
            }
            didChange()
        }
    }

    /// The built-in preprocessors that are on; always a subset of `optionalPreprocessors`.
    var builtInPreprocessors: Set<MarkdownTransform> {
        get {
            guard isPersistent else {
                return memory.builtInPreprocessors
            }
            let stored = defaults.stringArray(forKey: Self.preprocessorsKey) ?? []
            return Set(stored.compactMap(MarkdownTransform.init(rawValue:))).intersection(Self.optionalPreprocessors)
        }
        set {
            let allowed = newValue.intersection(Self.optionalPreprocessors)
            guard allowed != builtInPreprocessors else {
                return
            }
            if isPersistent {
                if allowed.isEmpty {
                    defaults.removeObject(forKey: Self.preprocessorsKey)
                } else {
                    defaults.set(
                        MarkdownTransform.allCases.filter(allowed.contains).map(\.rawValue),
                        forKey: Self.preprocessorsKey)
                }
            } else {
                memory.builtInPreprocessors = allowed
            }
            didChange()
        }
    }

    private func didChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
