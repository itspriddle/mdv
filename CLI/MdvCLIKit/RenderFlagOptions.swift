import ArgumentParser
import MdvCore

/// Headless render options (#65): frontmatter display, wiki links, source lines, highlighting,
/// remote images, and frontmatter diagnostics.
public struct RenderFlagOptions: ParsableArguments, Sendable {
    public init() {}

    /// Sets this group's `RenderOptions`. Today: the defaults (GFM, frontmatter hidden, no wiki
    /// links, no `data-source-line`, highlighting on, remote images kept).
    func apply(to options: inout RenderOptions) {}

    /// The renderer for one input, so a wiki link resolver can depend on the input's folder.
    func renderer(options: RenderOptions, for source: InputSource) -> HTMLRenderer {
        HTMLRenderer(options: options)
    }

    /// Reports what a render noticed (e.g. ignored frontmatter keys) on standard error.
    func report(_ rendered: RenderedDocument, for source: InputSource, in environment: CLIEnvironment) {}
}
