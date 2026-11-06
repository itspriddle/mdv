import Markdown

/// Converts Markdown source into an HTML fragment (the contents of `<body>`).
public protocol MarkdownRenderer: Sendable {
    func renderBody(_ markdown: String) -> String
}

/// Skeleton renderer backed by swift-markdown's built-in `HTMLFormatter`.
///
/// M1 replaces this with a custom `MarkupVisitor` that controls heading anchors,
/// task lists, emoji, raw HTML policy, and source-line mapping.
public struct SwiftMarkdownRenderer: MarkdownRenderer {
    public init() {}

    public func renderBody(_ markdown: String) -> String {
        let document = Document(parsing: markdown)
        return HTMLFormatter.format(document)
    }
}
