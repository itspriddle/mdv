import Foundation

/// What following a link in a rendered document does (#19).
public enum LinkAction: Equatable, Sendable {
    /// An in-page link: scroll to the element the fragment names (`fragmentIDCandidates`). The
    /// fragment is raw, as in the URL (percent-encoded, no `#`); empty for a bare `#`.
    case scrollToFragment(String)
    /// A local Markdown file: open it in mdv, then scroll to `fragment` (raw) if there is one.
    case openDocument(URL, fragment: String?)
    /// Any other local file or folder: reveal it in Finder. Never opened with its default app,
    /// since that would let a document launch apps and scripts (`.app`, `.command`, ...).
    case revealInFinder(URL)
    /// `http`, `https`, or `mailto`: open in the default app.
    case openExternal(URL)
    /// Anything else: other schemes (`javascript:`, `data:`, custom), links that name nothing
    /// (the blank `href` cmark's safe mode writes for `file:` and `javascript:` links), and
    /// links to the current document without a fragment. Nothing happens; the UI says why.
    case blocked(URL)
}

/// Where the document being shown lives, for deciding which links stay in it.
///
/// Kept separate from the policy so the way the page is loaded can change (e.g. a
/// `WKURLSchemeHandler` serving the page from a custom scheme) without changing the policy:
/// such a loader supplies its own `pageURL` and `localFile` mapping.
public struct LinkContext: Sendable {
    /// The URL the page was loaded from, without a fragment. Links that resolve to it (plus a
    /// fragment) are in-page links. `nil` before a page is loaded.
    public var pageURL: URL?
    /// The document's file on disk, if any. Links to it are in-page links too.
    public var documentFileURL: URL?
    /// The local file a resolved link URL names, or `nil` when it names none. The default
    /// (`fileURL(for:)`) accepts local `file:` URLs only.
    public var localFile: @Sendable (URL) -> URL?

    public init(
        pageURL: URL?,
        documentFileURL: URL?,
        localFile: @escaping @Sendable (URL) -> URL? = LinkContext.fileURL(for:)
    ) {
        self.pageURL = pageURL
        self.documentFileURL = documentFileURL
        self.localFile = localFile
    }

    /// The file a local `file:` URL names (standardized, without query or fragment), else `nil`.
    @Sendable
    public static func fileURL(for url: URL) -> URL? {
        guard url.isFileURL, url.host(percentEncoded: false).map({ $0.isEmpty || $0 == "localhost" }) ?? true
        else {
            return nil
        }
        let path = url.path(percentEncoded: false)
        guard path.hasPrefix("/") else {
            return nil
        }
        return URL(filePath: path).standardizedFileURL
    }
}

/// The viewer's navigation policy: maps a clicked link's resolved URL to a `LinkAction`. Every
/// link in the document web view goes through `action(for:in:)`; the main frame never navigates
/// away from the rendered document.
public enum LinkPolicy {
    /// Schemes handed to the default app.
    public static let externalSchemes: Set<String> = ["http", "https", "mailto"]

    /// File name extensions mdv opens as Markdown. Must match the `net.daringfireball.markdown`
    /// declaration in project.yml (an app test checks the built Info.plist).
    public static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    public static func action(for url: URL, in context: LinkContext) -> LinkAction {
        let fragment = url.fragment(percentEncoded: true)
        let target = url.withoutFragment ?? url
        if isCurrentDocument(target, in: context) {
            guard let fragment else {
                return .blocked(url)
            }
            return .scrollToFragment(fragment)
        }
        if let scheme = url.scheme?.lowercased(), externalSchemes.contains(scheme) {
            return .openExternal(url)
        }
        guard let file = context.localFile(target) else {
            return .blocked(url)
        }
        if isMarkdownFile(file) {
            return .openDocument(file, fragment: fragment)
        }
        return .revealInFinder(file)
    }

    /// Whether `url` (without a fragment) is the page or the document's file.
    private static func isCurrentDocument(_ url: URL, in context: LinkContext) -> Bool {
        if let page = context.pageURL?.withoutFragment, url.absoluteString == page.absoluteString {
            return true
        }
        guard let document = context.documentFileURL, let file = context.localFile(url) else {
            return false
        }
        return file.standardizedFileURL.path(percentEncoded: false)
            == document.standardizedFileURL.path(percentEncoded: false)
    }

    /// Whether mdv opens `url` as a Markdown document, by extension (case-insensitive).
    public static func isMarkdownFile(_ url: URL) -> Bool {
        !url.hasDirectoryPath && markdownExtensions.contains(url.pathExtension.lowercased())
    }

    /// The element ids to try, in order, for a raw (percent-encoded) fragment: the fragment as
    /// written, then percent-decoded (as browsers do), then each with the `user-content-` prefix
    /// the sanitizer gives raw HTML ids. Empty for an empty fragment.
    public static func fragmentIDCandidates(_ fragment: String) -> [String] {
        guard !fragment.isEmpty else {
            return []
        }
        var ids = [fragment]
        if let decoded = fragment.removingPercentEncoding, decoded != fragment, !decoded.isEmpty {
            ids.append(decoded)
        }
        ids += ids.map { HTMLSanitizerPolicy.userContentPrefix + $0 }
        return ids
    }

    /// Whether a fragment with no matching element means the top of the page (`#` and `#top`,
    /// as in browsers).
    public static func fragmentMeansTop(_ fragment: String) -> Bool {
        fragment.isEmpty || fragment.lowercased() == "top"
    }

    /// The text the hover overlay shows for a link: where it goes, and for links that don't
    /// navigate the usual way, what happens instead.
    public static func statusText(for action: LinkAction) -> String {
        switch action {
        case .scrollToFragment(let fragment):
            return "#" + (fragment.removingPercentEncoding ?? fragment)
        case .openDocument(let file, let fragment):
            let suffix = fragment.map { "#" + ($0.removingPercentEncoding ?? $0) } ?? ""
            return displayPath(file) + suffix
        case .revealInFinder(let file):
            return "Show in Finder: " + displayPath(file)
        case .openExternal(let url):
            return url.absoluteString
        case .blocked(let url):
            return "Blocked link: " + url.absoluteString
        }
    }

    private static func displayPath(_ file: URL) -> String {
        (file.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}

extension URL {
    /// This URL without its `#fragment`.
    public var withoutFragment: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.fragment = nil
        return components.url
    }
}
