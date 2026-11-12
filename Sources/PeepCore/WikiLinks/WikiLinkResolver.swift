/// Finds the file a wiki link's page names (#53). Injected into `HTMLRenderer`
/// (`wikiLinkResolver`), so PeepCore never touches the file system itself: the app passes a
/// `FolderWikiLinkResolver` over the real folders; tests pass fakes.
///
/// A renderer asks once per distinct page in a render. Resolvers are made for one render, so
/// a page that appears or disappears later is picked up by the next render (a live reload or a
/// reopen), never by watching targets.
public protocol WikiLinkResolver: Sendable {
    /// The file `page` names, as a path relative to the linking document's folder: `/`-separated
    /// and not percent-encoded (`Page-Name.md`, `guides/Setup.md`, `../notes/Page.md`). `nil`
    /// when no file matches; the link then renders as missing.
    func destination(for page: WikiPage) -> String?
}

/// A wiki link node's target (`MarkdownNode.Kind.wikiLink`), parsed from `[[target|label]]`.
public struct WikiLink: Sendable, Equatable {
    /// The target as written, trimmed (`Page Name#Heading`).
    public var target: String
    /// The page part, or `nil` for a same-document link (`[[#Heading]]`) or a name that names no
    /// page (`WikiPage.init?`).
    public var page: WikiPage?
    /// The heading part after `#`, trimmed, or `nil`. It links to the heading's slug.
    public var heading: String?
    /// The `href`, already percent-encoded: the resolved file's relative path (plus `#slug`), or
    /// `#slug` for a same-document link. `nil` for a missing page, which renders with no `href`.
    public var destination: String?

    public init(target: String, page: WikiPage?, heading: String?, destination: String?) {
        self.target = target
        self.page = page
        self.heading = heading
        self.destination = destination
    }

    /// Whether the link found nothing to point at (`wikilink-missing`).
    public var isMissing: Bool { destination == nil }
}
