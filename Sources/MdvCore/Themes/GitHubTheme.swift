extension Theme {
    /// The default theme: github.com's Markdown file view (Primer), light and dark. The vendored
    /// github-markdown-css (`GitHubMarkdownCSS`, `make vendor-github-markdown-css`) plus mdv's
    /// page layout, heading anchors, and highlight.js token colors from Primer's syntax palette.
    public static let github = Theme(
        id: "github",
        displayName: "GitHub",
        // Primer `--bgColor-default`, light and dark.
        background: ThemeBackground(light: ThemeColor(0xFF_FF_FF), dark: ThemeColor(0x0D_11_17)),
        stylesheet: GitHubMarkdownCSS.stylesheet + "\n" + GitHubTheme.stylesheet,
        highlightStylesheet: GitHubTheme.highlightStylesheet,
        printStylesheet: GitHubTheme.printStylesheet)
}

enum GitHubTheme {
    /// mdv's additions after the vendored CSS. github-markdown-css styles `.markdown-body` only
    /// and leaves the page layout to the host; this is github.com's README column. The page
    /// background comes from `Theme.background`, so `.markdown-body` is transparent over it.
    static let stylesheet = """
        body { margin: 0; }
        .markdown-body {
          box-sizing: border-box; min-width: 200px; max-width: var(--mdv-content-width, 980px); margin: 0 auto;
          padding: 32px 45px; font-size: var(--mdv-font-size, 16px); background-color: transparent;
        }
        /* Heading anchors: mdv writes an empty `a.anchor` (no octicon SVG, and theme CSS can't use a
           data: URL for its mask), so a "#" glyph stands in, shown on hover or focus. */
        .markdown-body h1, .markdown-body h2, .markdown-body h3,
        .markdown-body h4, .markdown-body h5, .markdown-body h6 { position: relative; }
        .markdown-body .anchor {
          position: absolute; left: -1em; float: none; width: 1em; margin: 0; padding: 0;
          line-height: inherit; text-align: center; color: var(--fgColor-muted); opacity: 0;
        }
        .markdown-body .anchor::before { content: "#"; }
        .markdown-body h1:hover .anchor, .markdown-body h2:hover .anchor, .markdown-body h3:hover .anchor,
        .markdown-body h4:hover .anchor, .markdown-body h5:hover .anchor, .markdown-body h6:hover .anchor,
        .markdown-body .anchor:focus { opacity: 1; }
        /* The frontmatter table (FrontmatterDisplay.table), as github.com shows it. */
        .markdown-body table.frontmatter th, .markdown-body table.frontmatter td {
          text-align: left; vertical-align: top;
        }
        """

    /// highlight.js tokens in Primer's syntax colors (`--color-prettylights-syntax-*`, which
    /// github.com uses for code), grouped as highlight.js's `github.css` groups them. The
    /// variables are github-markdown-css's, redefined for dark mode there, so one palette covers
    /// both appearances.
    static let highlightStylesheet = HighlightPalette.stylesheet(
        light: HighlightPalette(
            keyword: prettylights("keyword"),
            title: prettylights("entity"),
            constant: prettylights("constant"),
            string: prettylights("string"),
            builtIn: prettylights("variable"),
            comment: prettylights("comment"),
            tag: prettylights("entity-tag"),
            plain: "var(--fgColor-default)",
            section: prettylights("markup-heading"),
            bullet: prettylights("markup-list"),
            addition: (prettylights("markup-inserted-text"), prettylights("markup-inserted-bg")),
            deletion: (prettylights("markup-deleted-text"), prettylights("markup-deleted-bg"))),
        dark: nil)

    /// Paper: no page background, links in the text color and underlined.
    static let printStylesheet = """
        body { background: none; }
        .markdown-body a { color: inherit; text-decoration: underline; }
        """

    private static func prettylights(_ name: String) -> String {
        "var(--color-prettylights-syntax-\(name))"
    }
}
