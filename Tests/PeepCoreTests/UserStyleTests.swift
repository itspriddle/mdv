import Testing

@testable import PeepCore

@Suite("UserStyle")
struct UserStyleTests {
    @Test("the theme default adds no rules, only the empty layer")
    func themeDefaults() {
        #expect(UserStyle.themeDefaults.css.isEmpty)
        #expect(UserStyle.themeDefaults.layerCSS == "@layer peep-user {\n\n}")
        #expect(ContentWidth.default == .theme)
    }

    @Test(
        "each width sets the custom property and the column's max-width",
        arguments: [(ContentWidth.narrow, "32em"), (.wide, "72em"), (.full, "none")])
    func widths(width: ContentWidth, value: String) {
        let css = UserStyle(contentWidth: width).css
        #expect(css.contains(":root { --peep-content-width: \(value); }"))
        #expect(css.contains(".markdown-body { max-width: var(--peep-content-width); }"))
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

    @Test("a custom width accepts only its range")
    func customRange() {
        for points in [0, -1, 319, 3001, Int.max] {
            #expect(CustomContentWidth(points: points) == nil, "\(points)")
        }
        #expect(CustomContentWidth(points: 320)?.cssValue == "320px")
        #expect(CustomContentWidth(points: 3000)?.cssValue == "3000px")
        #expect(CustomContentWidth(points: 800)?.displayName == "Custom: 800px")
        #expect(CustomContentWidth(points: CustomContentWidth.defaultPoints) != nil)
    }

    @Test("a custom width beats every preset and sizes the text, not the padding")
    func customWins() throws {
        let custom = try #require(CustomContentWidth(points: 800))
        let expected = """
            @media screen {
              :root { --peep-content-width: 800px; }
              .markdown-body { max-width: var(--peep-content-width); box-sizing: content-box; }
            }
            """
        for width in ContentWidth.allCases {
            #expect(UserStyle(contentWidth: width, customWidth: custom).css == expected)
            #expect(UserStyle(contentWidth: width, customWidth: nil).css == UserStyle(contentWidth: width).css)
        }
        #expect(UserStyle(customWidth: custom) != UserStyle.themeDefaults)
    }

    @Test("the page has a user layer element after the theme's")
    func inDocument() throws {
        let html = HTMLDocument(
            title: "t", body: "", theme: .github, userStyle: UserStyle(contentWidth: .narrow)
        ).html
        let theme = try #require(html.range(of: "<style id=\"peep-theme\">"))
        let user = try #require(html.range(of: "<style id=\"peep-user\">\n@layer peep-user {"))
        #expect(theme.upperBound < user.lowerBound)
        #expect(html.contains("--peep-content-width: 32em;"))
        let plain = HTMLDocument(title: "t", body: "", theme: .github).html
        #expect(plain.contains("<style id=\"peep-user\">\n@layer peep-user {\n\n}\n</style>"))
    }
}
