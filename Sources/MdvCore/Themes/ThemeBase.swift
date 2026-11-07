/// The base layer every page gets under its theme: the rules viewer features depend on.
///
/// It sits in the first cascade layer (`ThemeLayer.base`). Ordinary declarations here are
/// defaults any theme may override. Declarations marked `!important` are protected: an
/// important declaration in an earlier layer beats important declarations in later layers and
/// unlayered CSS, so no theme (bundled or custom, layered or not) can undo them. The sanitizer
/// strips `style` attributes, so element-attached styles can't either. Protected:
///
/// - `.sr-only` (visually hidden text for assistive technology);
/// - find highlights (`::highlight(mdv-find)`, `::highlight(mdv-find-current)`, #25), never
///   printed;
/// - the blocked remote-image placeholder's visibility (#20) (its look is a default);
/// - GitHub's `#gh-dark-mode-only` / `#gh-light-mode-only` hiding (`ColorModeImage`);
/// - structural print rules (#26): light color scheme, full width, nothing clipped, no anchor
///   icons, sensible page breaks. External link targets written out on paper are a default.
public enum ThemeBase {
    public static let css = """
        :root { color-scheme: light dark; }
        .sr-only {
          position: absolute !important; width: 1px !important; height: 1px !important;
          padding: 0 !important; margin: -1px !important; overflow: hidden !important;
          clip: rect(0, 0, 0, 0) !important; white-space: nowrap !important; border: 0 !important;
        }
        /* Blocked remote images (#20): a labeled placeholder. Themes may restyle it, not hide it. */
        .remote-image {
          display: inline-flex; flex-direction: column; justify-content: center; align-items: center;
          box-sizing: border-box; max-width: 100%; min-height: 1.75em; padding: 2px 8px; overflow: hidden;
          vertical-align: middle; border: 1px dashed #d1d9e0; border-radius: 6px;
          color: #59636e; background: #f6f8fa; font-size: 0.75em; line-height: 1.3; text-align: center;
        }
        .remote-image { display: inline-flex !important; visibility: visible !important; }
        .remote-image-host { opacity: 0.75; }
        /* Find in page (the app's find bar): every match, and the current one. Never printed. */
        ::highlight(mdv-find) { background-color: rgb(255 214 0 / 0.4) !important; }
        ::highlight(mdv-find-current) { background-color: #ff9632 !important; color: #1f2328 !important; }
        /* Dark colors are for the screen only: paper is always printed with the light colors. */
        @media screen and (prefers-color-scheme: dark) {
          ::highlight(mdv-find) { background-color: rgb(255 214 0 / 0.3) !important; }
          ::highlight(mdv-find-current) { background-color: #ffb454 !important; color: #0d1117 !important; }
          .remote-image { color: #9198a1; background: #151b23; border-color: #3d444d; }
        }
        /* Print (#26): full width, nothing clipped, no hover-only anchor icons, link targets
           written out after external links. Pages break around code, rows, and images where
           they fit, and never right after a heading. */
        @media print {
          ::highlight(mdv-find), ::highlight(mdv-find-current) {
            background-color: transparent !important; color: inherit !important;
          }
          :root { color-scheme: light !important; }
          .markdown-body { max-width: none !important; padding: 0 !important; }
          .anchor { display: none !important; }
          a[href^="http:"]::after, a[href^="https:"]::after {
            content: " (" attr(href) ")"; font-size: 0.8em; overflow-wrap: anywhere;
          }
          pre { overflow: visible !important; white-space: pre-wrap !important; overflow-wrap: anywhere !important; }
          pre code { white-space: pre-wrap !important; }
          code { overflow-wrap: anywhere !important; }
          table { display: table !important; width: 100% !important; overflow: visible !important; }
          thead { display: table-header-group !important; }
          th, td { overflow-wrap: anywhere !important; }
          tr, img, .remote-image { break-inside: avoid !important; }
          img { max-width: 100% !important; }
          h1, h2, h3, h4, h5, h6 { break-after: avoid !important; }
        }
        /* GitHub's theme-specific images (`ColorModeImage`), and their remote-image placeholders:
           `#gh-dark-mode-only` shows only in dark mode, `#gh-light-mode-only` only in light mode
           and on paper (print is always light). Media queries follow appearance changes live. */
        @media not screen and (prefers-color-scheme: dark) {
          \(hidingRule(for: .dark))
        }
        @media screen and (prefers-color-scheme: dark) {
          \(hidingRule(for: .light))
        }
        """

    /// Hides the images (and placeholders) meant only for the other appearance. More specific
    /// than the placeholder's protected `display`, so it wins within this layer.
    private static func hidingRule(for mode: ColorModeImage) -> String {
        "img[src$=\"#\(mode.fragment)\"], .remote-image.\(mode.fragment) { display: none !important; }"
    }
}
