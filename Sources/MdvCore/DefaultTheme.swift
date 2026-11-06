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
        table.frontmatter { margin-bottom: 16px; border-collapse: collapse; font-size: 0.875em; }
        .frontmatter th, .frontmatter td {
          padding: 4px 8px; border: 1px solid #d1d9e0; text-align: left; vertical-align: top;
        }
        @media (prefers-color-scheme: dark) {
          body { color: #e6edf3; background: #0d1117; }
          pre { background: #161b22; }
          a { color: #4493f8; }
          .frontmatter th, .frontmatter td { border-color: #3d444d; }
        }
        """
}
