import UniformTypeIdentifiers

/// The Markdown content types Peep declares in its Info.plist (`project.yml`): both open as
/// `MarkdownDocument` with `LSHandlerRank` `Alternate` (#23).
enum MarkdownContentTypes {
    /// `.md`, `.markdown`, and `text/markdown`. macOS declares this type; Peep's imported
    /// declaration only stands in on a system that doesn't.
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")

    /// `.mdown`, `.mkd`, and `.mkdn`: Peep's own exported type, conforming to `markdown`.
    ///
    /// The system's `markdown` declaration lists only `md` and `markdown`, and an imported
    /// declaration never overrides a system one, so without this type those extensions resolve
    /// to a dynamic type (no document class) on a Mac where no other app declares them. The
    /// identifier is the bundle identifier plus `.markdown` (`PRODUCT_BUNDLE_IDENTIFIER_BASE`).
    static let otherMarkdownExtensions = UTType(exportedAs: "now.peep.Peep.markdown", conformingTo: markdown)

    /// Every Markdown type Peep declares as a handler, `markdown` first.
    static let all = [markdown, otherMarkdownExtensions]
}
