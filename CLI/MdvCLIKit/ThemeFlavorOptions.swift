import ArgumentParser
import MdvCore

/// `--theme` and `--flavor` (#64). Used by headless output and, for `--theme`, by `mdv FILE` in
/// the app (#67 reads this group from `MdvCommand.themeFlavor`).
public struct ThemeFlavorOptions: ParsableArguments, Sendable {
    public init() {}

    /// Sets the flavor a render starts from (frontmatter `mdv.flavor` may still change it).
    func apply(to options: inout RenderOptions) {}

    /// The page's theme for `--html`: the document's bundled `mdv.theme`, else GitHub. Custom and
    /// unknown ids are GitHub.
    func theme(for rendered: RenderedDocument) -> Theme {
        ThemeRegistry.bundled.theme(id: rendered.overrides.theme)
    }
}
