/// Stage 1 of the render pipeline (see `HTMLRenderer.render(_:)`): a whole-file text pass that
/// runs before anything else, frontmatter included (#56's custom preprocessor runner conforms;
/// the app enables it only by explicit opt-in, #57).
///
/// Its output replaces the source for every later stage, so `data-source-line` values, outline
/// positions, and the reading position kept across reloads all refer to lines of the
/// **preprocessor's output**, not of the file on disk. A preprocessor that keeps line structure
/// (expands text in place) keeps them aligned with the file; one that adds or removes lines
/// shifts them. Frontmatter is extracted from the output too, so a preprocessor can add, change,
/// or drop it.
///
/// Built-in syntax features are not preprocessors in this sense: they are `MarkdownTransform`s
/// over the AST (stage 5).
public protocol SourcePreprocessor: Sendable {
    /// The Markdown to render in place of `source`. Throws when the pass fails; the caller
    /// decides what to show (#57).
    func preprocess(_ source: String) async throws -> String
}

extension MarkdownRenderer {
    /// The whole pipeline: `source` through `preprocessor` (stage 1, if any), then `render(_:)`.
    /// Errors are the preprocessor's; cancellation is checked before rendering, so a newer render
    /// can drop this one.
    public func render(_ source: String, preprocessor: (any SourcePreprocessor)?) async throws
        -> RenderedDocument
    {
        guard let preprocessor else {
            return render(source)
        }
        let markdown = try await preprocessor.preprocess(source)
        try Task.checkCancellation()
        return render(markdown)
    }
}
