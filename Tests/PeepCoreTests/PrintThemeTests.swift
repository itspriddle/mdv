import Foundation
import Testing

@testable import PeepCore

/// Print themes (#38): the generated print CSS per theme and the base layer's paper
/// guarantees. The printed result in real WebKit (fonts, sizes, fills, `<picture>` light
/// images, dark mode) is checked by the app's `PrintThemeTests`, PDF per theme and appearance.
@Suite("Print themes")
struct PrintThemeTests {
    static let themes = ThemeRegistry.bundled.themes

    /// The contents of every top-level `@media print { ... }` block in `css`.
    static func printBlocks(in css: String) -> [String] {
        var blocks: [String] = []
        var rest = css[...]
        while let start = rest.range(of: "@media print {") {
            var depth = 1
            var index = start.upperBound
            while index < rest.endIndex, depth > 0 {
                if rest[index] == "{" { depth += 1 }
                if rest[index] == "}" { depth -= 1 }
                index = rest.index(after: index)
            }
            blocks.append(String(rest[start.upperBound..<rest.index(before: index)]))
            rest = rest[index...]
        }
        return blocks
    }

    // MARK: Generated print CSS

    @Test("each bundled theme ends with its print stylesheet in @media print", arguments: themes)
    func generatedPrintCSS(theme: Theme) throws {
        let printStylesheet = try #require(theme.printStylesheet)
        #expect(theme.css.hasSuffix("@media print {\n\(printStylesheet)\n}"))
        #expect(Self.printBlocks(in: theme.css) == ["\n\(printStylesheet)\n"], "one print block, the theme's")
        #expect(theme.layerCSS.contains("@media print {\n\(printStylesheet)\n}"), "inside the theme layer")
    }

    @Test("bundled print CSS is light only and leaves layout to the base layer", arguments: themes)
    func printCSSIsLooksOnly(theme: Theme) throws {
        let css = try #require(theme.printStylesheet)
        #expect(!css.contains("prefers-color-scheme"), "paper has one appearance")
        #expect(!css.contains("!important"), "the base layer's protected rules win anyway")
        #expect(!css.contains("max-width"), "content width (#37) never applies to paper")
        // Light fills are kept for code, keys, highlights, and tables, and nothing else.
        #expect(
            css.contains(
                """
                .markdown-body pre, .markdown-body code, .markdown-body kbd, .markdown-body mark,
                .markdown-body table { print-color-adjust: exact; }
                """), "\(theme.id)")
        #expect(css.components(separatedBy: "print-color-adjust").count == 2, "\(theme.id): one opt-in")
        #expect(!css.contains(/(^|[\s,}])(:root|html|body)\s*\{/), "\(theme.id): no page-level rules on paper")
    }

    @Test("paper text sizes: GitHub 16px, Document 11pt, Serif down from 19px to 15px")
    func paperTextSizes() throws {
        #expect(!(try #require(Theme.github.printStylesheet)).contains("font-size"))
        #expect(!(try #require(Theme.document.printStylesheet)).contains("font-size"))
        #expect(Theme.github.stylesheet.contains("font-size: 16px"))
        #expect(Theme.document.stylesheet.contains("font-size: 11pt"))
        #expect(Theme.serif.stylesheet.contains("font-size: 19px"))
        #expect(try #require(Theme.serif.printStylesheet).contains(".markdown-body { padding: 0; font-size: 15px; }"))
    }

    @Test("Document drops the desk on paper; GitHub and Document print links in the text color")
    func themeSpecificPrintRules() throws {
        let document = try #require(Theme.document.printStylesheet)
        #expect(document.contains(".markdown-body { margin: 0; background: none; box-shadow: none; }"))
        #expect(document.contains(".markdown-body a { color: inherit; }"))
        let github = try #require(Theme.github.printStylesheet)
        #expect(github.contains(".markdown-body a { color: inherit; text-decoration: underline; }"))
    }

    // MARK: Base layer

    @Test("the base layer keeps paper light: no page background, light color scheme, both protected")
    func basePaperIsLight() throws {
        let blocks = Self.printBlocks(in: ThemeBase.css)
        #expect(blocks.count == 1)
        let css = try #require(blocks.first)
        #expect(css.contains(":root { color-scheme: light !important; }"))
        #expect(css.contains(":root, body { print-color-adjust: economy !important; }"))
        #expect(css.contains("p { orphans: 3; widows: 3; }"), "a default, not protected")
        #expect(css.contains(".markdown-body { max-width: none !important; padding: 0 !important; }"))
    }
}
