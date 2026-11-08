/// A named Markdown dialect: the syntax a document is parsed and transformed with (#51).
///
/// A flavor owns **syntax** only: the cmark-gfm extensions the parser enables and the built-in AST
/// transforms that give text its meaning in that dialect (emoji shortcodes; GitHub alerts, #52).
/// Viewer and safety features are independent of the flavor and stay on `RenderOptions`: heading
/// anchors, highlighting, source lines, frontmatter detection and display, sanitizing, the remote
/// image policy, `linkRoot`, the HTML markup style (`gfmMarkup`), and opt-in built-in
/// preprocessors (`RenderOptions.builtInPreprocessors`, e.g. wiki links, #53).
///
/// Flavors are plain values: `RenderOptions.flavor` holds one, and `FlavorRegistry` resolves the
/// ids saved in settings and frontmatter. Adding a flavor is a `static let` here plus one line in
/// `FlavorRegistry.bundled`, and a fixture folder (`Tests/MdvCoreTests/Fixtures/flavors/<id>`).
public struct Flavor: Sendable, Hashable, Identifiable {
    /// Stable identifier, saved in preferences and read from frontmatter (e.g. `gfm`).
    public var id: String
    /// The name shown in Settings.
    public var displayName: String
    /// Syntax extensions the parser enables on top of CommonMark.
    public var extensions: Set<MarkdownExtension>
    /// AST transforms this flavor always runs. They run in `MarkdownTransform`'s declaration
    /// order, not in any order given here.
    public var transforms: Set<MarkdownTransform>

    public init(
        id: String, displayName: String, extensions: Set<MarkdownExtension>, transforms: Set<MarkdownTransform> = []
    ) {
        self.id = id
        self.displayName = displayName
        self.extensions = extensions
        self.transforms = transforms
    }
}

extension Flavor {
    /// GitHub Flavored Markdown as github.com renders it (the default): every extension (tables,
    /// strikethrough, extended autolinks, task lists, footnotes) and emoji shortcodes.
    public static let gfm = Flavor(
        id: "gfm", displayName: "GitHub Flavored Markdown", extensions: MarkdownExtension.gfm,
        transforms: [.emojiShortcodes])

    /// Strict CommonMark: no extensions and no transforms, so tables, task lists, strikethrough,
    /// extended autolinks, footnotes, and emoji shortcodes stay literal text. Frontmatter is
    /// still detected (it's metadata, not syntax; `RenderOptions.detectsFrontmatter`).
    public static let commonmark = Flavor(id: "commonmark", displayName: "CommonMark", extensions: [])
}
