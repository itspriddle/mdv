extension Theme {
    /// A quiet reading theme: the system serif (New York) in a narrow column on warm paper, few
    /// rules and muted code. Light and dark.
    public static let serif = Theme(
        id: "serif",
        displayName: "Serif",
        background: ThemeBackground(light: ThemeColor(0xFC_FB_F8), dark: ThemeColor(0x1B_1A_18)),
        stylesheet: SerifTheme.stylesheet,
        highlightStylesheet: SerifTheme.highlightStylesheet,
        printStylesheet: SerifTheme.printStylesheet)
}

enum SerifTheme {
    static let stylesheet = """
        .markdown-body {
          --serif-text: #26241f; --serif-muted: #6f6a60; --serif-accent: #9a4a1c; --serif-rule: #e2ddd2;
          --serif-code-bg: #f3f0e8;
          --serif-note: #2e6a8a; --serif-tip: #4f7a3a; --serif-important: #5b4a8a; --serif-warning: #8a5d12;
          --serif-caution: #9a3a1c;
        }
        @media screen and (prefers-color-scheme: dark) {
          .markdown-body {
            --serif-text: #e6e2d9; --serif-muted: #9d978b; --serif-accent: #e3a06b; --serif-rule: #3a3833;
            --serif-code-bg: #25231f;
            --serif-note: #8fbcd4; --serif-tip: #a8c99a; --serif-important: #c2b0e6; --serif-warning: #e0c27a;
            --serif-caution: #e89a7a;
          }
        }
        body { margin: 0; }
        .markdown-body {
          box-sizing: border-box; max-width: var(--mdv-content-width, 40em); margin: 0 auto;
          padding: 56px 32px 72px; color: var(--serif-text);
          font-family: ui-serif, "New York", Charter, Georgia, "Times New Roman", serif;
          font-size: 19px; line-height: 1.65;
          overflow-wrap: break-word; hanging-punctuation: first; font-kerning: normal;
        }
        .markdown-body > :first-child { margin-top: 0; }
        .markdown-body > :last-child { margin-bottom: 0; }
        .markdown-body p, .markdown-body ul, .markdown-body ol, .markdown-body dl, .markdown-body table,
        .markdown-body pre, .markdown-body blockquote, .markdown-body details { margin: 0 0 1.1em; }
        .markdown-body h1, .markdown-body h2, .markdown-body h3,
        .markdown-body h4, .markdown-body h5, .markdown-body h6 {
          position: relative; margin: 1.8em 0 0.6em; font-weight: 600; line-height: 1.25;
        }
        .markdown-body h1 { font-size: 2em; margin-top: 0.5em; font-weight: 700; }
        .markdown-body h2 { font-size: 1.5em; }
        .markdown-body h3 { font-size: 1.2em; }
        .markdown-body h4 { font-size: 1em; }
        .markdown-body h5 { font-size: 1em; font-weight: 400; font-style: italic; }
        .markdown-body h6 {
          font-size: 0.8em; font-weight: 400; letter-spacing: 0.08em; text-transform: uppercase;
          color: var(--serif-muted);
        }
        .markdown-body .anchor {
          position: absolute; left: -1em; width: 1em; text-align: center; text-decoration: none;
          color: var(--serif-muted); opacity: 0;
        }
        .markdown-body .anchor::before { content: "§"; }
        .markdown-body h1:hover .anchor, .markdown-body h2:hover .anchor, .markdown-body h3:hover .anchor,
        .markdown-body h4:hover .anchor, .markdown-body h5:hover .anchor, .markdown-body h6:hover .anchor,
        .markdown-body .anchor:focus { opacity: 1; }
        .markdown-body a {
          color: inherit; text-decoration: underline; text-decoration-color: var(--serif-muted);
          text-decoration-thickness: 1px; text-underline-offset: 0.18em;
        }
        .markdown-body a:hover { color: var(--serif-accent); text-decoration-color: currentColor; }
        .markdown-body ul, .markdown-body ol { padding-left: 1.6em; }
        .markdown-body li + li { margin-top: 0.3em; }
        .markdown-body li > ul, .markdown-body li > ol { margin: 0.3em 0 0; }
        .markdown-body .contains-task-list { padding-left: 1.2em; }
        .markdown-body .task-list-item { list-style-type: none; }
        .markdown-body .task-list-item-checkbox { margin: 0 0.4em 0.2em -1.3em; vertical-align: middle; }
        .markdown-body blockquote {
          margin-left: 0; padding: 0 0 0 1.2em; border-left: 2px solid var(--serif-rule);
          color: var(--serif-muted); font-style: italic;
        }
        .markdown-body blockquote em { font-style: normal; }
        /* GitHub alerts: a margin note, a thin colored rule with a small-caps title, upright text. */
        .markdown-body .markdown-alert {
          margin: 0 0 1.1em; padding: 0 0 0 1.2em; border-left: 2px solid var(--serif-alert);
        }
        .markdown-body .markdown-alert > :last-child { margin-bottom: 0; }
        .markdown-body .markdown-alert-title {
          margin-bottom: 0.35em; color: var(--serif-alert); font-variant-caps: all-small-caps;
          letter-spacing: 0.06em;
        }
        .markdown-body .markdown-alert-title svg { width: 0.85em; height: 0.85em; }
        .markdown-body .markdown-alert-note { --serif-alert: var(--serif-note); }
        .markdown-body .markdown-alert-tip { --serif-alert: var(--serif-tip); }
        .markdown-body .markdown-alert-important { --serif-alert: var(--serif-important); }
        .markdown-body .markdown-alert-warning { --serif-alert: var(--serif-warning); }
        .markdown-body .markdown-alert-caution { --serif-alert: var(--serif-caution); }
        /* A section break: three spaced asterisks instead of a line. */
        .markdown-body hr { height: auto; margin: 2.2em 0; border: 0; text-align: center; color: var(--serif-muted); }
        .markdown-body hr::before { content: "* * *"; letter-spacing: 0.6em; }
        .markdown-body img { max-width: 100%; box-sizing: content-box; }
        .markdown-body code, .markdown-body kbd, .markdown-body pre, .markdown-body samp {
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.8em;
        }
        .markdown-body code { padding: 0.1em 0.3em; border-radius: 3px; background: var(--serif-code-bg); }
        .markdown-body pre {
          padding: 14px 18px; overflow: auto; line-height: 1.5; border-radius: 4px; background: var(--serif-code-bg);
        }
        .markdown-body pre code { padding: 0; font-size: 1em; background: none; }
        .markdown-body kbd { padding: 0.05em 0.35em; border: 1px solid var(--serif-rule); border-radius: 3px; }
        /* Tables: rules above, below, and under the header only (book style). */
        .markdown-body table {
          display: block; width: max-content; max-width: 100%; overflow: auto; border-collapse: collapse;
          font-size: 0.9em; font-variant-numeric: lining-nums tabular-nums;
          border-top: 1px solid var(--serif-muted); border-bottom: 1px solid var(--serif-muted);
        }
        .markdown-body th, .markdown-body td { padding: 6px 14px 6px 0; }
        .markdown-body th:not([align]) { text-align: left; }
        .markdown-body th { font-weight: 600; border-bottom: 1px solid var(--serif-rule); }
        .markdown-body tbody tr + tr td { border-top: 1px solid var(--serif-rule); }
        .markdown-body table.frontmatter th, .markdown-body table.frontmatter td { vertical-align: top; }
        .markdown-body table.frontmatter th { border-bottom: 0; }
        .markdown-body dt { font-style: italic; }
        .markdown-body dd { margin: 0 0 0.5em 1.5em; }
        .markdown-body .footnotes {
          margin-top: 3em; padding-top: 1em; border-top: 1px solid var(--serif-rule);
          font-size: 0.85em; color: var(--serif-muted);
        }
        .markdown-body sup > a[data-footnote-ref] { text-decoration: none; color: var(--serif-accent); }
        """

    /// Muted, low-contrast token colors that sit with body text, light and dark.
    static let highlightStylesheet =
        HighlightPalette.stylesheet(
            light: HighlightPalette(
                keyword: "#8a4a2a", title: "#5b4a8a", constant: "#2e6a8a", string: "#4f7a3a", builtIn: "#946519",
                comment: "#8b877e", tag: "#8a4a2a", plain: "inherit", section: "#2e6a8a", bullet: "#946519",
                addition: ("#3d6a2a", "#e9f0df"), deletion: ("#8a2a2a", "#f5e3df")),
            dark: HighlightPalette(
                keyword: "#e0a07a", title: "#c2b0e6", constant: "#8fbcd4", string: "#a8c99a", builtIn: "#e0c27a",
                comment: "#8a867d", tag: "#e0a07a", plain: "inherit", section: "#8fbcd4", bullet: "#e0c27a",
                addition: ("#b9dca8", "#26331e"), deletion: ("#f0b4a8", "#3d2420")))
        + "\n.hljs-comment { font-style: italic; }"

    /// Paper: the column fills the printable width at a book's text size. The screen's 19px
    /// would be over 15pt on paper (WebKit lays pages out 1.25 times the paper's width in CSS
    /// pixels); 15px prints at 12pt. Headings and code are in em, so they follow.
    static let printStylesheet = """
        .markdown-body { padding: 0; font-size: 15px; }
        /* Code, keys, highlights, and tables keep their light fills (WebKit leaves backgrounds off
           on paper otherwise), so code blocks and diff lines still read as blocks. */
        .markdown-body pre, .markdown-body code, .markdown-body kbd, .markdown-body mark,
        .markdown-body table { print-color-adjust: exact; }
        """
}
