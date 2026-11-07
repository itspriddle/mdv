import Foundation
import Testing

@testable import MdvCore

@Suite("Bundled themes")
struct BundledThemeTests {
    static let themes = ThemeRegistry.bundled.themes

    @Test("GitHub, Document, and Serif are registered, GitHub first and the default")
    func registered() {
        #expect(ThemeRegistry.bundled.themes.map(\.id) == ["github", "document", "serif"])
        #expect(ThemeRegistry.bundled.defaultTheme == .github)
        #expect(Set(ThemeRegistry.bundled.themes.map(\.displayName)).count == 3)
        for theme in Self.themes {
            #expect(ThemeRegistry.bundled.theme(id: theme.id) == theme)
            // Display names avoid other companies' product names (Docs, Pages, Word).
            #expect(!["Google", "Docs", "Word", "Pages"].contains { theme.displayName.contains($0) })
        }
    }

    @Test("a background per appearance, dark darker than light", arguments: themes)
    func backgrounds(theme: Theme) {
        let light = theme.background.light
        let dark = theme.background.dark
        #expect(light != dark)
        #expect(Self.luminance(dark) < Self.luminance(light))
        #expect(Self.luminance(light) > 0.8)
        #expect(Self.luminance(dark) < 0.2)
    }

    @Test("the page background comes from Theme.background, not the stylesheet", arguments: themes)
    func noBodyBackground(theme: Theme) {
        let bodyBackground = /(^|[\s,}])body\s*\{[^}]*background/
        #expect(theme.stylesheet.firstMatch(of: bodyBackground) == nil)
        #expect(theme.highlightStylesheet.firstMatch(of: bodyBackground) == nil)
    }

    @Test("light and dark variants: dark rules on screen only", arguments: themes)
    func darkVariant(theme: Theme) {
        #expect(theme.stylesheet.contains("@media screen and (prefers-color-scheme: dark)"))
        #expect(!theme.css.contains("@media (prefers-color-scheme"))
    }

    @Test("highlight token colors for every token group, light and dark", arguments: themes)
    func highlightTokens(theme: Theme) throws {
        let css = theme.highlightStylesheet
        for token in [
            ".hljs-keyword", ".hljs-title", ".hljs-number", ".hljs-string", ".hljs-built_in", ".hljs-comment",
            ".hljs-name", ".hljs-addition", ".hljs-deletion",
        ] {
            #expect(css.contains(token), "\(theme.id): missing \(token)")
        }
        if theme == .github {
            // One palette of Primer variables, which the vendored CSS defines once per appearance.
            for variable in Set(css.matches(of: /var\((--color-prettylights-syntax-[a-z-]+)\)/).map { $0.1 }) {
                let definitions = theme.stylesheet.components(separatedBy: "\(variable):").count - 1
                #expect(definitions == 2, "\(variable) is defined \(definitions) times")
            }
        } else {
            let dark = try #require(css.range(of: "@media screen and (prefers-color-scheme: dark)"))
            #expect(css[dark.upperBound...].contains(".hljs-keyword"))
        }
    }

    @Test("styles mdv's own markup: anchors, task lists, footnotes, frontmatter, tables, code", arguments: themes)
    func mdvMarkup(theme: Theme) {
        for selector in [
            ".anchor::before", ".task-list-item", "table.frontmatter", ".markdown-body pre", ".markdown-body table",
            "footnote",
        ] {
            #expect(theme.css.contains(selector), "\(theme.id): missing \(selector)")
        }
    }

    @Test("content width reads the user-control variable (#37)", arguments: themes)
    func userControlVariables(theme: Theme) {
        #expect(theme.stylesheet.contains("max-width: var(--mdv-content-width, "))
    }

    @Test("system fonts only", arguments: themes)
    func systemFonts(theme: Theme) {
        #expect(!theme.css.contains("@font-face"))
        #expect(!theme.css.contains("font-src"))
        #expect(theme.css.contains("ui-monospace"))
    }

    @Test("braces balance, so no rule escapes the theme layer", arguments: themes)
    func balancedBraces(theme: Theme) {
        var depth = 0
        for character in theme.css {
            if character == "{" { depth += 1 }
            if character == "}" { depth -= 1 }
            #expect(depth >= 0, "\(theme.id): unbalanced }")
            if depth < 0 { return }
        }
        #expect(depth == 0, "\(theme.id): unclosed {")
    }

    @Test("the vendored GitHub CSS is pinned and adjusted: screen-only dark, no url()")
    func vendoredGitHubCSS() {
        let css = GitHubMarkdownCSS.stylesheet
        #expect(GitHubMarkdownCSS.version == "5.9.0")
        #expect(css.contains("@media screen and (prefers-color-scheme: dark) {"))
        #expect(css.contains("@media not screen and (prefers-color-scheme: dark) {"))
        #expect(!css.contains("url("))
        #expect(!css.contains("</"))
        // mdv's additions come after the vendored CSS so they win at equal specificity.
        let vendored = Theme.github.stylesheet.range(of: css)
        let additions = Theme.github.stylesheet.range(of: GitHubTheme.stylesheet)
        #expect(vendored?.lowerBound == Theme.github.stylesheet.startIndex)
        if let vendored, let additions {
            #expect(vendored.upperBound <= additions.lowerBound)
        }
    }

    @Test("the showcase fixture renders every construct in every theme", arguments: themes)
    func showcase(theme: Theme) throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(components: "..", "..", "AppUITests", "Fixtures", "themes", "showcase.md")
        let source = try String(contentsOf: url, encoding: .utf8)
        var options = RenderOptions()
        options.frontmatterDisplay = .table
        options.remoteImages = .block
        let rendered = HTMLRenderer(options: options).render(source)
        let html = HTMLDocument(title: rendered.title ?? "", body: rendered.html, theme: theme).html
        for markup in [
            "<table class=\"frontmatter\">", "class=\"anchor\"", "<h6", "class=\"task-list-item\"", "<blockquote>",
            "<del>", "<kbd>", "class=\"hljs-keyword\"", "class=\"hljs-string\"", "class=\"hljs-comment\"",
            "class=\"hljs-addition\"", "<table>", "class=\"footnotes\"", "<img src=\"assets/shape.svg\"",
            "class=\"remote-image\"", "gh-dark-mode-only", "<details>", "<hr",
        ] {
            #expect(html.contains(markup), "\(theme.id): missing \(markup)")
        }
        #expect(html.contains(theme.layerCSS))
    }

    /// Relative luminance (WCAG), 0 (black) to 1 (white).
    static func luminance(_ color: ThemeColor) -> Double {
        func channel(_ value: UInt8) -> Double {
            let srgb = Double(value) / 255
            return srgb <= 0.039_28 ? srgb / 12.92 : pow((srgb + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }
}
