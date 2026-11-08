// Source line annotations for `HTMLRenderer` (#9).

extension HTMLRenderer {
    /// Writes ` data-source-line="N"` for a block element when `options.sourceLines` is on.
    ///
    /// Contract for the app's scroll sync and position-preserving reload (M2):
    ///
    /// - `N` is the 1-based line, in the text `render(_:)` was given, where the block's Markdown
    ///   starts: the file, or the custom preprocessor's output when one ran (#51; see
    ///   `SourcePreprocessor`). Frontmatter lines count (the parser already offsets body lines
    ///   past it), and a CRLF or CR line ending counts as one line break, like LF. AST
    ///   transforms keep these lines: nodes they add carry the range of the text they replace.
    /// - Annotated elements: `p`, `h1`–`h6`, `blockquote`, `ul`/`ol`, `li` (list, task, and
    ///   footnote items), `pre`, `table`, `tr`, and `hr`. Values never decrease in document
    ///   order before the footnotes section, so a reader can binary-search them there. Footnote
    ///   items come last, in number order (first reference), wherever they were defined, so
    ///   their lines can go back.
    /// - Not annotated: inline elements, table cells (a row is one line), the footnotes
    ///   `section`, frontmatter tables, and raw HTML blocks. User HTML is never rewritten for
    ///   this; scroll sync interpolates between the annotated neighbors of a raw HTML block.
    /// - A paragraph in a tight list item has no `<p>`; its `li` carries the line.
    /// - Nodes without a source position (trees built in code) get no attribute.
    ///
    /// The value is an integer we produce, so it needs no escaping.
    func writeSourceLine(of node: MarkdownNode, into output: inout HTMLOutput) {
        guard options.sourceLines, let line = node.sourceRange?.start.line else {
            return
        }
        output.raw(" data-source-line=\"\(line)\"")
    }

    /// Starts a block element: `<tag data-source-line="N">` on a new line.
    func openBlock(_ tag: String, _ node: MarkdownNode, into output: inout HTMLOutput) {
        output.newlineIfNeeded()
        output.raw("<\(tag)")
        writeSourceLine(of: node, into: &output)
        output.raw(">")
    }
}
