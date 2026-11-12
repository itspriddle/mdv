import Testing

@testable import MdvCore

@Suite("UserStyle")
struct UserStyleTests {
    @Test("the theme default adds no rules, only the empty layer")
    func themeDefaults() {
        #expect(UserStyle.themeDefaults.css.isEmpty)
        #expect(UserStyle.themeDefaults.layerCSS == "@layer mdv-user {\n\n}")
        #expect(ContentWidth.default == .theme)
    }

    @Test(
        "each width sets the custom property and the column's max-width",
        arguments: [(ContentWidth.narrow, "32em"), (.wide, "72em"), (.full, "none")])
    func widths(width: ContentWidth, value: String) {
        let css = UserStyle(contentWidth: width).css
        #expect(css.contains(":root { --mdv-content-width: \(value); }"))
        #expect(css.contains(".markdown-body { max-width: var(--mdv-content-width); }"))
    }

    @Test("widths are screen only, so paper is always full width")
    func screenOnly() throws {
        for width in ContentWidth.allCases where width.cssValue != nil {
            let css = UserStyle(contentWidth: width).css
            #expect(css.hasPrefix("@media screen {"))
            #expect(css.hasSuffix("}"))
            #expect(!css.contains("print"))
        }
        #expect(ThemeBase.css.contains(".markdown-body { max-width: none !important;"))
    }

    @Test("presets are fixed constants with menu titles")
    func presets() {
        #expect(ContentWidth.narrow.cssValue == "32em")
        #expect(ContentWidth.wide.cssValue == "72em")
        #expect(ContentWidth.theme.cssValue == nil)
        #expect(ContentWidth.allCases.map(\.displayName) == ["Narrow", "Theme Default", "Wide", "Full Width"])
    }

    @Test("stored values are parsed strictly")
    func rawValues() {
        #expect(ContentWidth(rawValue: "wide") == .wide)
        #expect(ContentWidth(rawValue: "Wide") == nil)
        #expect(ContentWidth(rawValue: "100px; } body { display: none") == nil)
        #expect(ContentWidth(rawValue: "") == nil)
    }

    @Test("the page has a user layer element after the theme's")
    func inDocument() throws {
        let html = HTMLDocument(
            title: "t", body: "", theme: .github, userStyle: UserStyle(contentWidth: .narrow)
        ).html
        let theme = try #require(html.range(of: "<style id=\"mdv-theme\">"))
        let user = try #require(html.range(of: "<style id=\"mdv-user\">\n@layer mdv-user {"))
        #expect(theme.upperBound < user.lowerBound)
        #expect(html.contains("--mdv-content-width: 32em;"))
        let plain = HTMLDocument(title: "t", body: "", theme: .github).html
        #expect(plain.contains("<style id=\"mdv-user\">\n@layer mdv-user {\n\n}\n</style>"))
    }
}
