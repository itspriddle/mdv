/// The flavors mdv knows, by id. The one place the app, the CLI, and frontmatter overrides (#54)
/// turn a flavor id into a `Flavor`: an id that is missing or unknown resolves to the default
/// (GFM), as `ThemeRegistry` does for themes.
public struct FlavorRegistry: Sendable, Equatable {
    /// The bundled flavors, default first: GFM, CommonMark.
    public static let bundled = FlavorRegistry(defaultFlavor: .gfm, others: [.commonmark])

    /// What an unknown id resolves to (GFM for the bundled registry).
    public let defaultFlavor: Flavor
    /// Every registered flavor in menu order, the default first. Ids are unique.
    public let flavors: [Flavor]

    /// A registry of `defaultFlavor` followed by `others`. A flavor whose id is already taken is
    /// dropped (the first one wins).
    public init(defaultFlavor: Flavor, others: [Flavor] = []) {
        self.defaultFlavor = defaultFlavor
        var seen: Set<String> = []
        self.flavors = ([defaultFlavor] + others).filter { seen.insert($0.id).inserted }
    }

    /// The flavor with `id`, or the default when `id` is nil or not registered. Ids match
    /// exactly (they are lowercase).
    public func flavor(id: String?) -> Flavor {
        guard let id, let flavor = flavors.first(where: { $0.id == id }) else {
            return defaultFlavor
        }
        return flavor
    }

    /// Whether a flavor with `id` is registered.
    public func contains(id: String) -> Bool {
        flavors.contains { $0.id == id }
    }
}
