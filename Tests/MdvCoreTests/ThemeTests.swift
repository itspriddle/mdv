import Foundation
import Testing

@testable import MdvCore

@Suite("Themes")
struct ThemeTests {
    /// A theme that tries to undo everything the base layer protects.
    static let hostile = Theme(
        id: "hostile", displayName: "Hostile", background: ThemeBackground(light: ThemeColor(0), dark: ThemeColor(0)),
        stylesheet: """
            } .sr-only { position: static !important; }
            ::highlight(mdv-find) { background-color: transparent !important; }
            .remote-image { display: none !important; }
            </style><script>alert(1)</script><style>
            """)

    @Test("writes colors as CSS hex")
    func hex() {
        #expect(ThemeColor(0x0D_11_17).hex == "#0d1117")
        #expect(ThemeColor(0xFF_FF_FF).hex == "#ffffff")
        #expect(ThemeColor(red: 1, green: 0xA0, blue: 0).hex == "#01a000")
    }

    @Test("the page background is generated from the background the app paints before first load")
    func background() throws {
        let css = Theme.github.css
        #expect(css.hasPrefix("body { background: \(Theme.github.background.light.hex); }"))
        let dark = try #require(css.range(of: "@media screen and (prefers-color-scheme: dark) {"))
        #expect(css[dark.upperBound...].hasPrefix("\n  body { background: \(Theme.github.background.dark.hex); }"))
    }

    @Test("a theme's print rules come last, in @media print")
    func printStylesheet() throws {
        let css = Theme.github.css
        let start = try #require(css.range(of: "@media print {", options: .backwards))
        #expect(css[start.upperBound...].contains(".markdown-body a { color: inherit; text-decoration: underline; }"))
        #expect(css.hasSuffix("}"))
        let bare = Theme(id: "b", displayName: "B", background: Theme.github.background, stylesheet: "p {}")
        #expect(!bare.css.contains("@media print"))
    }

    @Test("dark colors are screen only")
    func screenOnlyDark() {
        for css in [ThemeBase.css] + ThemeRegistry.bundled.themes.map(\.css) {
            #expect(css.contains("@media screen and (prefers-color-scheme: dark)"))
            #expect(!css.contains("@media (prefers-color-scheme: dark)"))
            #expect(!css.contains("@media (prefers-color-scheme: light)"))
        }
    }

    @Test("structural print rules are protected: light, unclipped code and tables, no anchors")
    func basePrintRules() throws {
        let css = ThemeBase.css
        let start = try #require(css.range(of: "@media print {"))
        let printRules = String(css[start.upperBound...])
        for rule in [
            ".anchor { display: none !important; }",
            "pre { overflow: visible !important; white-space: pre-wrap !important;",
            // Vendored GitHub CSS sets `pre > code { white-space: pre }`, which would clip on paper.
            "pre code { white-space: pre-wrap !important; }",
            "table { display: table !important; width: 100% !important; overflow: visible !important; }",
            ":root { color-scheme: light !important; }", #"a[href^="https:"]::after"#,
            ".markdown-body { max-width: none !important; padding: 0 !important; }",
        ] {
            #expect(printRules.contains(rule), "missing \(rule)")
        }
    }

    @Test("find highlights, placeholders, and .sr-only are protected")
    func protectedRules() {
        let css = ThemeBase.css
        for rule in [
            "::highlight(mdv-find) { background-color: rgb(255 214 0 / 0.4) !important; }",
            "::highlight(mdv-find-current) { background-color: #ff9632 !important;",
            ".remote-image { display: inline-flex !important; visibility: visible !important; }",
            "position: absolute !important;",
        ] {
            #expect(css.contains(rule), "missing \(rule)")
        }
    }

    @Test("the page declares base, theme, user layers in order, each in its own style element")
    func layers() throws {
        let html = HTMLDocument(title: "t", body: "", theme: .github).html
        #expect(ThemeLayer.orderStatement == "@layer mdv-base, mdv-theme, mdv-user;")
        let order = try #require(html.range(of: ThemeLayer.orderStatement))
        let base = try #require(
            html.range(of: "<style id=\"mdv-base\">\n@layer mdv-base, mdv-theme, mdv-user;\n@layer mdv-base {"))
        let theme = try #require(html.range(of: "<style id=\"mdv-theme\">\n@layer mdv-theme {"))
        #expect(base.upperBound > order.lowerBound)
        #expect(base.lowerBound < theme.lowerBound)
        #expect(html.components(separatedBy: "@layer").count == 4)  // statement + two blocks
    }

    @Test("theme CSS can't close its style element")
    func inlineSafe() {
        let html = HTMLDocument(title: "t", body: "", theme: Self.hostile).html
        #expect(!html.contains("</style><script>"))
        #expect(html.contains(#"<\/style><script>"#))
        #expect(html.components(separatedBy: "</style>").count == 3)
        #expect(ThemeLayer.inlineSafe("a::after { content: \"</STYLE>\"; }") == #"a::after { content: "<\/STYLE>"; }"#)
    }

    @Test("every registered theme's page has the base layer, below the theme", arguments: ThemeRegistry.bundled.themes)
    func baseInEveryTheme(theme: Theme) throws {
        let html = HTMLDocument(title: "t", body: "", theme: theme).html
        let base = try #require(html.range(of: ThemeBase.layerCSS))
        let themeLayer = try #require(html.range(of: theme.layerCSS))
        #expect(base.upperBound <= themeLayer.lowerBound)
        for rule in ["::highlight(mdv-find)", ".remote-image", "gh-dark-mode-only", ".sr-only", "@media print"] {
            #expect(html.contains(rule), "missing \(rule)")
        }
        #expect(theme.css.contains(theme.background.light.hex))
        #expect(theme.css.contains(theme.background.dark.hex))
        #expect(!theme.displayName.isEmpty)
    }

    @Test("bundled theme CSS loads nothing remote")
    func noRemoteLoads() {
        for css in [ThemeBase.css] + ThemeRegistry.bundled.themes.map(\.css) {
            #expect(!css.contains("@import"))
            #expect(!css.contains("url("))
            #expect(!css.contains("@font-face"))
        }
    }
}

@Suite("ThemeRegistry")
struct ThemeRegistryTests {
    func theme(_ id: String) -> Theme {
        Theme(id: id, displayName: id.uppercased(), background: Theme.github.background, stylesheet: "")
    }

    @Test("GitHub is the bundled default")
    func bundledDefault() {
        #expect(ThemeRegistry.bundled.defaultTheme.id == "github")
        #expect(ThemeRegistry.bundled.themes.first == .github)
        #expect(ThemeRegistry.bundled.contains(id: "github"))
    }

    @Test("an unknown, missing, or empty id falls back to the default", arguments: [nil, "", "nope", "GitHub"])
    func fallback(id: String?) {
        #expect(ThemeRegistry.bundled.theme(id: id) == ThemeRegistry.bundled.defaultTheme)
    }

    @Test("resolves registered ids")
    func resolves() {
        let registry = ThemeRegistry(defaultTheme: theme("a"), others: [theme("b")])
        #expect(registry.theme(id: "b").id == "b")
        #expect(registry.theme(id: "a").id == "a")
        #expect(registry.themes.map(\.id) == ["a", "b"])
    }

    @Test("added themes go last and can't replace a registered id")
    func adding() {
        let registry = ThemeRegistry(defaultTheme: theme("a"), others: [theme("b")])
        var shadow = theme("a")
        shadow.displayName = "Shadow"
        let added = registry.adding([theme("c"), shadow, theme("c")])
        #expect(added.themes.map(\.id) == ["a", "b", "c"])
        #expect(added.theme(id: "a").displayName == "A")
        #expect(added.defaultTheme.id == "a")
        // A removed theme (a deleted custom file) falls back to the default.
        #expect(registry.theme(id: "c").id == "a")
    }

    @Test("the picker lists bundled themes, then added ones, in separate sections")
    func pickerSections() {
        let base = ThemeRegistry(defaultTheme: theme("a"), others: [theme("b")])
        #expect(base.pickerSections(base: base).map { $0.map(\.id) } == [["a", "b"]])
        let added = base.adding([theme("c"), theme("d")])
        #expect(added.pickerSections(base: base).map { $0.map(\.id) } == [["a", "b"], ["c", "d"]])
        #expect(ThemeRegistry.bundled.pickerSections() == [ThemeRegistry.bundled.themes])
    }
}
