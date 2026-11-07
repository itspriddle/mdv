/// Colors for highlight.js's `hljs-*` token classes, grouped the way highlight.js's own
/// `github.css` groups them. Values are any CSS color (a hex literal or a `var(…)`).
///
/// Bundled themes build their `highlightStylesheet` from one palette per appearance, so every
/// theme colors the same token groups and none forgets the dark variant.
struct HighlightPalette: Sendable {
    /// Keywords, types, template tags, `self`/`this`.
    var keyword: String
    /// Function and class names.
    var title: String
    /// Numbers, literals, attributes, operators, variables, CSS selectors.
    var constant: String
    /// Strings and regular expressions.
    var string: String
    /// Built-ins and symbols.
    var builtIn: String
    var comment: String
    /// Tag names, quotes, CSS element selectors.
    var tag: String
    /// Substitutions, emphasis, strong: the code's own text color.
    var plain: String
    /// Markup headings (e.g. in diff or Markdown code blocks).
    var section: String
    /// List bullets in Markdown code blocks.
    var bullet: String
    var addition: (color: String, background: String)
    var deletion: (color: String, background: String)

    /// The token rules for this palette.
    var rules: String {
        """
        .hljs-doctag, .hljs-keyword, .hljs-meta .hljs-keyword, .hljs-template-tag,
        .hljs-template-variable, .hljs-type, .hljs-variable.language_ { color: \(keyword); }
        .hljs-title, .hljs-title.class_, .hljs-title.class_.inherited__, .hljs-title.function_ { color: \(title); }
        .hljs-attr, .hljs-attribute, .hljs-literal, .hljs-meta, .hljs-number, .hljs-operator, .hljs-variable,
        .hljs-selector-attr, .hljs-selector-class, .hljs-selector-id { color: \(constant); }
        .hljs-regexp, .hljs-string, .hljs-meta .hljs-string { color: \(string); }
        .hljs-built_in, .hljs-symbol { color: \(builtIn); }
        .hljs-comment, .hljs-code, .hljs-formula { color: \(comment); }
        .hljs-name, .hljs-quote, .hljs-selector-tag, .hljs-selector-pseudo { color: \(tag); }
        .hljs-subst, .hljs-emphasis, .hljs-strong { color: \(plain); }
        .hljs-section { color: \(section); }
        .hljs-bullet { color: \(bullet); }
        .hljs-addition { color: \(addition.color); background-color: \(addition.background); }
        .hljs-deletion { color: \(deletion.color); background-color: \(deletion.background); }
        """
    }

    /// The highlight stylesheet: weights and styles, `light` colors, then `dark` colors on
    /// screen only (paper always prints light). With no `dark` palette, `light` must adapt by
    /// itself (e.g. CSS variables the theme redefines for dark mode).
    static func stylesheet(light: HighlightPalette, dark: HighlightPalette?) -> String {
        var css = """
            .hljs-section, .hljs-strong { font-weight: bold; }
            .hljs-emphasis { font-style: italic; }
            \(light.rules)
            """
        if let dark {
            css += "\n@media screen and (prefers-color-scheme: dark) {\n\(dark.rules)\n}"
        }
        return css
    }
}
