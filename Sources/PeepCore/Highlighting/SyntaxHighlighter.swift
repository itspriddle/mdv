/// Turns source code into highlighted HTML for a fenced code block.
///
/// `HTMLRenderer` calls this for code blocks whose info string names a language, then passes
/// the result through `HighlightValidator` before using it, so an implementation is never
/// trusted to produce safe markup. Implementations must be safe to call from any thread.
public protocol SyntaxHighlighter: Sendable {
    /// Highlights `code` as `language` (the first word of the info string, as written).
    ///
    /// Returns HTML made only of `<span class="…">` elements around entity-escaped text whose
    /// unescaped text is exactly `code`, or `nil` for an unknown language or any failure.
    func highlight(_ code: String, language: String) -> String?
}
