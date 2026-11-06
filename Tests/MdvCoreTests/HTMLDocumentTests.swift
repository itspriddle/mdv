import Testing

@testable import MdvCore

@Suite("HTMLDocument")
struct HTMLDocumentTests {
    @Test("wraps body with CSP and stylesheet")
    func wraps() {
        let html = HTMLDocument(title: "Doc", body: "<p>hi</p>", stylesheet: "body{}").html
        #expect(html.contains("Content-Security-Policy"))
        #expect(html.contains("default-src 'none'"))
        #expect(html.contains("<p>hi</p>"))
        #expect(html.contains("body{}"))
    }

    @Test("escapes the title")
    func escapesTitle() {
        let html = HTMLDocument(title: "<script>&", body: "").html
        #expect(html.contains("<title>&lt;script&gt;&amp;</title>"))
    }
}

@Suite("DefaultTheme")
struct DefaultThemeTests {
    @Test("writes colors as CSS hex")
    func hex() {
        #expect(ThemeColor(0x0D_11_17).hex == "#0d1117")
        #expect(ThemeColor(0xFF_FF_FF).hex == "#ffffff")
        #expect(ThemeColor(red: 1, green: 0xA0, blue: 0).hex == "#01a000")
    }

    @Test("the stylesheet uses the background the app paints before first load")
    func background() {
        #expect(DefaultTheme.css.contains("background: \(DefaultTheme.background.light.hex);"))
        #expect(DefaultTheme.css.contains("background: \(DefaultTheme.background.dark.hex); }"))
    }

    @Test("dark colors are screen only, and print rules unclip code and tables and hide anchors")
    func print() throws {
        let css = DefaultTheme.css
        #expect(css.contains("@media screen and (prefers-color-scheme: dark)"))
        #expect(!css.contains("@media (prefers-color-scheme: dark)"))
        let start = try #require(css.range(of: "@media print {"))
        let printRules = String(css[start.upperBound...])
        for rule in [
            ".anchor { display: none; }", "pre { overflow: visible; white-space: pre-wrap;",
            "table { display: table; width: 100%; overflow: visible; }", ":root { color-scheme: light; }",
            #"a[href^="https:"]::after"#,
        ] {
            #expect(printRules.contains(rule), "missing \(rule)")
        }
    }
}
