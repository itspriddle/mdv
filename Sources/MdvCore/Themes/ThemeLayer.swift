/// The page's CSS cascade layers, lowest priority first: base → theme → user controls.
///
/// Layers, not concatenation order, decide precedence (settled in #31, recorded in
/// `docs/VISION.md`):
/// - a later layer beats an earlier one for ordinary declarations whatever their specificity,
///   so a theme's `.markdown-body pre` can't out-rank user controls (#37) and themes don't need
///   to know what else is on the page;
/// - for `!important` declarations the order reverses, so the base layer's protected rules
///   (`ThemeBase`) win over every theme, even one that escapes its layer or marks its own rules
///   important.
///
/// Each layer is its own `<style id="mdv-…">` element, so the theme (#34) or user controls
/// (#37) can be swapped in place by replacing one element's text.
public enum ThemeLayer: String, Sendable, CaseIterable {
    case base = "mdv-base"
    case theme = "mdv-theme"
    case user = "mdv-user"

    /// The cascade layer name, also the id of the layer's `<style>` element.
    public var name: String { rawValue }

    /// Declares the layer order. Goes first on the page, before any layer's rules.
    public static var orderStatement: String {
        "@layer \(allCases.map(\.name).joined(separator: ", "));"
    }

    /// `css` inside this layer's `@layer` block, made safe to inline in a `<style>` element.
    public func wrap(_ css: String) -> String {
        "@layer \(name) {\n\(Self.inlineSafe(css))\n}"
    }

    /// `css` with every `</` written as `<\/`, so it can't close its `<style>` element and
    /// inject markup (HTML ends raw text at `</style`). CSS has no valid `</` outside strings and
    /// comments, and `\/` is `/` inside a string, so the stylesheet means the same.
    public static func inlineSafe(_ css: String) -> String {
        css.replacing("</", with: #"<\/"#)
    }
}

extension ThemeBase {
    /// The base layer's contents for its `<style>` element: the layer order, then the rules.
    public static let layerCSS = ThemeLayer.orderStatement + "\n" + ThemeLayer.base.wrap(css)
}

extension Theme {
    /// The theme layer's contents for its `<style>` element (`ThemeLayer.theme`). An in-place
    /// theme switch replaces that element's text with this.
    public var layerCSS: String {
        ThemeLayer.theme.wrap(css)
    }
}
