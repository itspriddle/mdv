/// A built-in AST pass, run between parsing and HTML (stage 5 of the render pipeline; see
/// `HTMLRenderer.render(_:)`).
///
/// Built-in syntax features are AST transforms, not text passes over the source: they rewrite
/// only `text` nodes the parser produced, so code spans, code blocks, raw HTML, and link
/// destinations are never touched, and every node keeps a source range, so `data-source-line`
/// stays correct. (Text passes would have to re-implement Markdown's code and HTML rules to stay
/// out of them.) Whole-file text rewriting is the custom preprocessor's job (stage 1, #56).
///
/// A transform is enabled by the flavor (`Flavor.transforms`, syntax that belongs to a dialect)
/// or by `RenderOptions.builtInPreprocessors` (opt-in features independent of the flavor).
/// Enabled transforms run in **declaration order below**, whatever order they were enabled in,
/// so output never depends on how a set was built. The planned order is:
///
/// 1. `alerts` (#52): block structure, so it runs first; it reads the `[!NOTE]` marker before
///    any inline transform could change that text.
/// 2. `wikiLinks` (#53): turns `[[Page]]` text into link nodes.
/// 3. `emojiShortcodes`: last, so it also converts shortcodes in text other transforms produce
///    (alert bodies, wiki link labels), as it does in ordinary link text.
///
/// Adding a transform: a case here at its place in that order, a type conforming to
/// `MarkdownTreeTransform`, one line in `implementation`, and the flavor (or toggle) that enables
/// it. Transforms run before sanitizing, heading collection, and highlighting, so heading text
/// and slugs see their result, and nodes they add are rendered (and escaped) by `HTMLRenderer`.
public enum MarkdownTransform: String, CaseIterable, Sendable, Hashable {
    /// GitHub alerts (`> [!NOTE]`) in top-level block quotes become `alert` nodes (#52). GFM only.
    case alerts

    /// Wiki links (`[[Page]]`) in text become links to the page's file (#53). An opt-in built-in
    /// preprocessor, independent of the flavor; resolved by `HTMLRenderer.wikiLinkResolver`.
    case wikiLinks

    /// GitHub emoji shortcodes (`:tada:`) in text become emoji (#10). GFM only.
    case emojiShortcodes = "emoji"

    /// The pass that implements this transform.
    var implementation: any MarkdownTreeTransform.Type {
        switch self {
        case .alerts: GitHubAlerts.self
        case .wikiLinks: WikiLinks.self
        case .emojiShortcodes: EmojiShortcodes.self
        }
    }

    /// `enabled` in pipeline order (declaration order).
    static func ordered(_ enabled: Set<MarkdownTransform>) -> [MarkdownTransform] {
        allCases.filter(enabled.contains)
    }

    /// Runs `context.options.transforms` (already in pipeline order) over `root`.
    static func apply(to root: MarkdownNode, context: TransformContext) -> MarkdownNode {
        context.options.transforms.reduce(root) { tree, transform in
            transform.implementation.apply(to: tree, context: context)
        }
    }
}

/// An AST pass behind a `MarkdownTransform` case.
///
/// Rules every implementation follows:
///
/// - Rewrite only what the parser left as `text` (and inline structure around it); never look
///   inside `code`, `codeBlock`, `htmlInline`, `htmlBlock`, or link destinations.
/// - Give every new node a `sourceRange` (usually the range of the text it replaces), so source
///   lines and outline positions survive the pass.
/// - Never build HTML. Produce `MarkdownNode`s (adding a `Kind` if needed) that `HTMLRenderer`
///   writes with escaping by construction.
/// - Be total and iterative: no recursion over the tree depth (see `MarkdownParser`'s nesting
///   limit), no throwing; input that doesn't match stays as it was.
protocol MarkdownTreeTransform {
    static func apply(to root: MarkdownNode, context: TransformContext) -> MarkdownNode
}

/// What a transform may read besides the tree. Built by `HTMLRenderer` for each render; add
/// fields here rather than reaching for globals.
struct TransformContext: Sendable {
    /// The options of the render in progress (with the flavor resolved for this document).
    var options: RenderOptions
    /// The text the tree was parsed from (the whole file, so source range lines match), or `nil`
    /// for a tree built elsewhere (`HTMLRenderer.html(for:)`).
    var source: String?
    /// Finds wiki link pages (#53); `nil` renders every page link as missing.
    var wikiLinkResolver: (any WikiLinkResolver)?

    init(options: RenderOptions, source: String? = nil, wikiLinkResolver: (any WikiLinkResolver)? = nil) {
        self.options = options
        self.source = source
        self.wikiLinkResolver = wikiLinkResolver
    }
}
