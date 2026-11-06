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
        @media (prefers-color-scheme: dark) {
          body { color: #e6edf3; background: #0d1117; }
          pre { background: #161b22; }
          a { color: #4493f8; }
          th, td, .footnotes { border-color: #3d444d; }
        }
        """
}
