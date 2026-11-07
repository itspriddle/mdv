extension Theme {
    /// A word processor's document: a letter-width page on a gray desk, a proportional sans,
    /// and document-style headings (Title, Heading 1, …). Light and dark.
    public static let document = Theme(
        id: "document",
        displayName: "Document",
        // The desk around the page.
        background: ThemeBackground(light: ThemeColor(0xEC_EE_F1), dark: ThemeColor(0x18_19_1B)),
        stylesheet: DocumentTheme.stylesheet,
        highlightStylesheet: DocumentTheme.highlightStylesheet,
        printStylesheet: DocumentTheme.printStylesheet)
}

enum DocumentTheme {
    static let stylesheet = """
        .markdown-body {
          --doc-page: #ffffff; --doc-text: #1f1f1f; --doc-muted: #5f6368; --doc-link: #1a5fb4;
          --doc-rule: #c7cad1; --doc-code-bg: #f1f3f5; --doc-header-bg: #f5f6f8;
          --doc-shadow: 0 1px 3px rgb(0 0 0 / 0.12), 0 4px 12px rgb(0 0 0 / 0.06);
        }
        @media screen and (prefers-color-scheme: dark) {
          .markdown-body {
            --doc-page: #25262a; --doc-text: #e3e3e6; --doc-muted: #a2a5ab; --doc-link: #82b1ff;
            --doc-rule: #45474d; --doc-code-bg: #2f3136; --doc-header-bg: #2c2d32;
            --doc-shadow: 0 1px 3px rgb(0 0 0 / 0.5);
          }
        }
        body { margin: 0; }
        /* The page: US Letter width (8.5in) with 1in margins, narrower windows get less margin. */
        .markdown-body {
          box-sizing: border-box; max-width: var(--mdv-content-width, 816px); margin: 32px auto; padding: 96px;
          background: var(--doc-page); box-shadow: var(--doc-shadow); color: var(--doc-text);
          font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif;
          font-size: 11pt; line-height: 1.5;
          overflow-wrap: break-word;
        }
        @media screen and (max-width: 880px) {
          .markdown-body { margin: 0 auto; padding: 48px 32px; box-shadow: none; }
        }
        .markdown-body > :first-child { margin-top: 0; }
        .markdown-body > :last-child { margin-bottom: 0; }
        .markdown-body p, .markdown-body ul, .markdown-body ol, .markdown-body dl, .markdown-body table,
        .markdown-body pre, .markdown-body blockquote, .markdown-body details { margin: 0 0 1em; }
        /* Document headings: Title, then Heading 1–4, regular weight like a word processor's. Sizes are
           26/20/16/14/12/11pt at the default 11pt, in em so they follow the font size. */
        .markdown-body h1, .markdown-body h2, .markdown-body h3,
        .markdown-body h4, .markdown-body h5, .markdown-body h6 {
          position: relative; margin: 1.25em 0 0.5em; font-weight: 400; line-height: 1.25;
        }
        .markdown-body h1 { font-size: 2.364em; margin-top: 0.5em; }
        .markdown-body h2 { font-size: 1.818em; }
        .markdown-body h3 { font-size: 1.455em; }
        .markdown-body h4 { font-size: 1.273em; color: var(--doc-muted); }
        .markdown-body h5 { font-size: 1.091em; font-weight: 600; color: var(--doc-muted); }
        .markdown-body h6 { font-size: 1em; font-style: italic; color: var(--doc-muted); }
        .markdown-body .anchor {
          position: absolute; left: -1em; width: 1em; text-align: center; text-decoration: none;
          color: var(--doc-muted); opacity: 0;
        }
        .markdown-body .anchor::before { content: "#"; }
        .markdown-body h1:hover .anchor, .markdown-body h2:hover .anchor, .markdown-body h3:hover .anchor,
        .markdown-body h4:hover .anchor, .markdown-body h5:hover .anchor, .markdown-body h6:hover .anchor,
        .markdown-body .anchor:focus { opacity: 1; }
        .markdown-body a { color: var(--doc-link); text-decoration: underline; text-underline-offset: 0.15em; }
        .markdown-body strong { font-weight: 600; }
        .markdown-body ul, .markdown-body ol { padding-left: 2em; }
        .markdown-body li + li, .markdown-body li > ul, .markdown-body li > ol { margin-top: 0.25em; }
        .markdown-body li > ul, .markdown-body li > ol { margin-bottom: 0; }
        .markdown-body .contains-task-list { padding-left: 1.5em; }
        .markdown-body .task-list-item { list-style-type: none; }
        .markdown-body .task-list-item-checkbox { margin: 0 0.35em 0.2em -1.4em; vertical-align: middle; }
        .markdown-body blockquote {
          padding: 0 1em; border-left: 3px solid var(--doc-rule); color: var(--doc-muted);
        }
        .markdown-body hr { height: 0; margin: 1.5em 0; border: 0; border-top: 1px solid var(--doc-rule); }
        .markdown-body img { max-width: 100%; box-sizing: content-box; }
        .markdown-body code, .markdown-body kbd, .markdown-body pre, .markdown-body samp {
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.875em;
        }
        .markdown-body code { padding: 0.15em 0.35em; border-radius: 4px; background: var(--doc-code-bg); }
        .markdown-body pre {
          padding: 12px 16px; overflow: auto; line-height: 1.45; border: 1px solid var(--doc-rule);
          border-radius: 4px; background: var(--doc-code-bg);
        }
        .markdown-body pre code { padding: 0; font-size: 1em; background: none; }
        .markdown-body kbd {
          padding: 0.1em 0.4em; border: 1px solid var(--doc-rule); border-radius: 4px;
          background: var(--doc-code-bg);
        }
        /* Tables: a full grid, like a word processor's default table. */
        .markdown-body table {
          display: block; width: max-content; max-width: 100%; overflow: auto; border-collapse: collapse;
          font-variant-numeric: tabular-nums;
        }
        .markdown-body th, .markdown-body td { padding: 5px 10px; border: 1px solid var(--doc-rule); }
        .markdown-body th { font-weight: 600; background: var(--doc-header-bg); }
        .markdown-body table.frontmatter { font-size: 0.875em; }
        .markdown-body table.frontmatter th, .markdown-body table.frontmatter td {
          text-align: left; vertical-align: top;
        }
        .markdown-body dt { font-weight: 600; }
        .markdown-body dd { margin: 0 0 0.5em 1.5em; }
        .markdown-body summary { cursor: default; }
        .markdown-body mark { padding: 0 0.1em; background: #fff2a8; color: #1f1f1f; }
        .markdown-body .footnotes {
          margin-top: 2em; padding-top: 0.75em; border-top: 1px solid var(--doc-rule);
          font-size: 0.875em; color: var(--doc-muted);
        }
        .markdown-body sup > a[data-footnote-ref] { text-decoration: none; }
        """

    /// Xcode-like token colors, light and dark.
    static let highlightStylesheet = HighlightPalette.stylesheet(
        light: HighlightPalette(
            keyword: "#9b2393", title: "#326d74", constant: "#1c00cf", string: "#c41a16", builtIn: "#3900a0",
            comment: "#5d6c79", tag: "#0b4f79", plain: "inherit", section: "#0b4f79", bullet: "#643820",
            addition: ("#1a6b2c", "#e6f4e8"), deletion: ("#a21a1a", "#fbe9e9")),
        dark: HighlightPalette(
            keyword: "#fc5fa3", title: "#67b7a4", constant: "#d0bf69", string: "#fc6a5d", builtIn: "#a167e6",
            comment: "#7f8c98", tag: "#5dd8ff", plain: "inherit", section: "#5dd8ff", bullet: "#fd8f3f",
            addition: ("#9ce0a9", "#1d3a24"), deletion: ("#ffb3ad", "#4a1f1f")))

    /// Paper is the page: no desk, no shadow, links in the text color.
    static let printStylesheet = """
        body { background: none; }
        .markdown-body { margin: 0; background: none; box-shadow: none; }
        .markdown-body a { color: inherit; }
        """
}
