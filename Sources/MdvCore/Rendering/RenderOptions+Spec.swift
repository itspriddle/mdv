extension RenderOptions {
    /// Spec mode: output comparable to cmark-gfm's reference HTML, for the CommonMark/GFM spec
    /// conformance suite (`SpecConformanceTests`).
    ///
    /// All GFM extensions are on (cmark-gfm runs `extensions.txt` that way; the suite narrows
    /// `extensions` per example for `spec.txt` and `regression.txt`), and every mdv-specific
    /// addition is off. A feature that adds a toggle to `RenderOptions` and changes the HTML
    /// (heading ids, source lines, sanitizing, emoji, highlighting, frontmatter, ...) turns
    /// itself off here with one line, e.g. `options.headingAnchors = false`.
    ///
    /// cmark's safe-mode URL filtering stays on: it is a security default, not an addition.
    public static var spec: RenderOptions {
        var options = RenderOptions(extensions: Set(MarkdownExtension.allCases))
        // Features: add `options.<toggle> = <off>` lines here.
        options.detectsFrontmatter = false
        options.gfmMarkup = .cmark
        options.headingAnchors = false
        options.highlighting = false
        options.sanitize = false
        return options
    }
}
