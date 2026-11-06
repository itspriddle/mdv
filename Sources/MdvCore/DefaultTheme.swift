/// Placeholder stylesheet until the theme system lands in M3.
public enum DefaultTheme {
    public static let css = """
        :root { color-scheme: light dark; }
        body {
          margin: 0;
          font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
          color: #1f2328;
          background: #ffffff;
        }
        .markdown-body { max-width: 860px; margin: 0 auto; padding: 32px; }
        pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.875em; }
        pre { padding: 16px; overflow: auto; border-radius: 6px; background: #f6f8fa; }
        a { color: #0969da; }
        table { border-collapse: collapse; display: block; max-width: 100%; overflow: auto; }
        th, td { padding: 6px 13px; border: 1px solid #d1d9e0; }
        th { font-weight: 600; }
        .task-list-item { list-style-type: none; }
        .task-list-item-checkbox { margin: 0 0.2em 0.25em -1.4em; vertical-align: middle; }
        .footnotes { margin-top: 2em; padding-top: 1em; border-top: 1px solid #d1d9e0; font-size: 0.875em; }
        .sr-only {
          position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
          overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0;
        }
        h1, h2, h3, h4, h5, h6 { position: relative; }
        .anchor {
          position: absolute; left: -1em; width: 1em; text-align: center; text-decoration: none; opacity: 0;
        }
        .anchor::before { content: "#"; }
        h1:hover .anchor, h2:hover .anchor, h3:hover .anchor,
        h4:hover .anchor, h5:hover .anchor, h6:hover .anchor, .anchor:focus { opacity: 1; }
        table.frontmatter { margin-bottom: 16px; font-size: 0.875em; }
        .frontmatter th, .frontmatter td {
          padding: 4px 8px; text-align: left; vertical-align: top;
        }
        /* Syntax highlighting: highlight.js 11 `github.css` and `github-dark.css` token colors
           (BSD-3-Clause, (c) 2006 Ivan Sagalaev and contributors; theme by @Hirse). */
        .hljs-doctag, .hljs-keyword, .hljs-meta .hljs-keyword, .hljs-template-tag,
        .hljs-template-variable, .hljs-type, .hljs-variable.language_ { color: #d73a49; }
        .hljs-title, .hljs-title.class_, .hljs-title.class_.inherited__, .hljs-title.function_ { color: #6f42c1; }
        .hljs-attr, .hljs-attribute, .hljs-literal, .hljs-meta, .hljs-number, .hljs-operator, .hljs-variable,
        .hljs-selector-attr, .hljs-selector-class, .hljs-selector-id { color: #005cc5; }
        .hljs-regexp, .hljs-string, .hljs-meta .hljs-string { color: #032f62; }
        .hljs-built_in, .hljs-symbol { color: #e36209; }
        .hljs-comment, .hljs-code, .hljs-formula { color: #6a737d; }
        .hljs-name, .hljs-quote, .hljs-selector-tag, .hljs-selector-pseudo { color: #22863a; }
        .hljs-subst { color: #24292e; }
        .hljs-section { color: #005cc5; font-weight: bold; }
        .hljs-bullet { color: #735c0f; }
        .hljs-emphasis { color: #24292e; font-style: italic; }
        .hljs-strong { color: #24292e; font-weight: bold; }
        .hljs-addition { color: #22863a; background-color: #f0fff4; }
        .hljs-deletion { color: #b31d28; background-color: #ffeef0; }
        @media (prefers-color-scheme: dark) {
          body { color: #e6edf3; background: #0d1117; }
          pre { background: #161b22; }
          a { color: #4493f8; }
          th, td, .footnotes { border-color: #3d444d; }
          .hljs-doctag, .hljs-keyword, .hljs-meta .hljs-keyword, .hljs-template-tag,
          .hljs-template-variable, .hljs-type, .hljs-variable.language_ { color: #ff7b72; }
          .hljs-title, .hljs-title.class_, .hljs-title.class_.inherited__, .hljs-title.function_ { color: #d2a8ff; }
          .hljs-attr, .hljs-attribute, .hljs-literal, .hljs-meta, .hljs-number, .hljs-operator, .hljs-variable,
          .hljs-selector-attr, .hljs-selector-class, .hljs-selector-id { color: #79c0ff; }
          .hljs-regexp, .hljs-string, .hljs-meta .hljs-string { color: #a5d6ff; }
          .hljs-built_in, .hljs-symbol { color: #ffa657; }
          .hljs-comment, .hljs-code, .hljs-formula { color: #8b949e; }
          .hljs-name, .hljs-quote, .hljs-selector-tag, .hljs-selector-pseudo { color: #7ee787; }
          .hljs-subst, .hljs-emphasis, .hljs-strong { color: #c9d1d9; }
          .hljs-section { color: #1f6feb; }
          .hljs-bullet { color: #f2cc60; }
          .hljs-addition { color: #aff5b4; background-color: #033a16; }
          .hljs-deletion { color: #ffdcd7; background-color: #67060c; }
        }
        """
}
