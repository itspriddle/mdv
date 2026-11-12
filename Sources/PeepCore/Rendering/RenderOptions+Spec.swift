extension RenderOptions {
    /// Spec mode: output comparable to cmark-gfm's reference HTML, for the CommonMark/GFM spec
    /// conformance suite (`SpecConformanceTests`).
    ///
    /// The flavor is `Flavor.spec`: all GFM extensions on (cmark-gfm runs `extensions.txt` that
    /// way; the suite narrows `flavor.extensions` per example for `spec.txt` and
    /// `regression.txt`) and no transforms. Every mdv-specific addition is off: a feature that
    /// adds a toggle to `RenderOptions` and changes the HTML (heading ids, source lines,
    /// sanitizing, highlighting, frontmatter, ...) turns itself off here with one line, e.g.
    /// `options.headingAnchors = false`. A new syntax transform needs no line: `Flavor.spec`
    /// runs none, and `builtInPreprocessors` is emptied.
    ///
    /// cmark's safe-mode URL filtering stays on: it is a security default, not an addition.
    public static var spec: RenderOptions {
        var options = RenderOptions(flavor: .spec)
        // Features: add `options.<toggle> = <off>` lines here.
        options.appliesDocumentOverrides = false
        options.builtInPreprocessors = []
        options.detectsFrontmatter = false
        options.gfmMarkup = .cmark
        options.headingAnchors = false
        options.highlighting = false
        options.linkRoot = nil
        options.remoteImages = .keep
        options.sanitize = false
        options.sourceLines = false
        return options
    }
}

extension Flavor {
    /// The spec suite's flavor (`RenderOptions.spec`): every extension, no transforms. Not a
    /// user-facing flavor, so it isn't in `FlavorRegistry`.
    public static let spec = Flavor(
        id: "spec", displayName: "Spec", extensions: Set(MarkdownExtension.allCases), transforms: [])
}
