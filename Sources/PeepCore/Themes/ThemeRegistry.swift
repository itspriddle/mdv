/// The themes Peep knows, by id. The one place the app and CLI ask for a theme: an id that is
/// missing, unknown, or no longer registered (a deleted custom theme) resolves to the default.
public struct ThemeRegistry: Sendable, Equatable {
    /// The bundled themes, default first: GitHub, Document, Serif.
    public static let bundled = ThemeRegistry(defaultTheme: .github, others: [.document, .serif])

    /// What an unknown id resolves to (GitHub for the bundled registry).
    public let defaultTheme: Theme
    /// Every registered theme in menu order: the default, the rest of the bundled themes, then
    /// any added later (custom themes, #35). Ids are unique.
    public let themes: [Theme]

    /// A registry of `defaultTheme` followed by `others`. A theme whose id is already taken is
    /// dropped (the first one wins), so a later theme can never replace an earlier one.
    public init(defaultTheme: Theme, others: [Theme] = []) {
        self.defaultTheme = defaultTheme
        self.themes = Self.unique([defaultTheme] + others)
    }

    /// The theme with `id`, or the default when `id` is nil or not registered.
    public func theme(id: String?) -> Theme {
        guard let id, let theme = themes.first(where: { $0.id == id }) else {
            return defaultTheme
        }
        return theme
    }

    /// Whether a theme with `id` is registered.
    public func contains(id: String) -> Bool {
        themes.contains { $0.id == id }
    }

    /// This registry plus `themes` after the existing ones (e.g. custom themes, #35). Themes
    /// whose id is already registered are dropped, so a custom theme can't shadow a bundled one.
    public func adding(_ themes: [Theme]) -> ThemeRegistry {
        ThemeRegistry(defaultTheme: defaultTheme, others: Array(self.themes.dropFirst()) + themes)
    }

    /// The themes as the theme picker lists them: the ones `base` also registers (the bundled
    /// themes), then the rest (added later: custom themes, #35), each group in registry order.
    /// Empty groups are left out, so a registry of bundled themes is one group.
    public func pickerSections(base: ThemeRegistry = .bundled) -> [[Theme]] {
        let bundled = themes.filter { base.contains(id: $0.id) }
        let added = themes.filter { !base.contains(id: $0.id) }
        return [bundled, added].filter { !$0.isEmpty }
    }

    private static func unique(_ themes: [Theme]) -> [Theme] {
        var seen: Set<String> = []
        return themes.filter { seen.insert($0.id).inserted }
    }
}
