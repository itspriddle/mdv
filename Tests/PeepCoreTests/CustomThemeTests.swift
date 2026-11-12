import Darwin
import Foundation
import Testing

@testable import MdvCore

/// Custom themes (#35): the header, the CSS checks (hostile inputs included), and reading the
/// folder.
@Suite("Custom themes")
struct CustomThemeTests {
    // MARK: Header

    @Test(
        "a file without a header is named after the file, starts from the base layer, and uses the default background")
    func noHeader() throws {
        let theme = try CustomTheme.make(fileName: "My Theme.css", css: "p { color: red; }")
        #expect(theme.id == "custom:My Theme.css")
        #expect(theme.displayName == "My Theme")
        #expect(theme.background == ThemeRegistry.bundled.defaultTheme.background)
        #expect(theme.stylesheet == "p { color: red; }")
        #expect(theme.highlightStylesheet.isEmpty)
        #expect(theme.printStylesheet == nil)
    }

    @Test("the header sets name, backgrounds, and the extended theme")
    func fullHeader() throws {
        let css = """

            /* mdv-theme
             * Name:  Solarized   Light
             * background: #FDF6E3
             * background-dark: #002b36
             * extends: serif
             */
            p { color: #586e75; }
            """
        let theme = try CustomTheme.make(fileName: "solarized.css", css: css)
        #expect(theme.displayName == "Solarized Light")
        #expect(theme.background == ThemeBackground(light: ThemeColor(0xFD_F6_E3), dark: ThemeColor(0x00_2B_36)))
        // The bundled theme's CSS first (all of it but its background), then the file.
        let serif = Theme.serif
        #expect(theme.stylesheet.hasPrefix(serif.stylesheet))
        #expect(theme.stylesheet.contains(serif.highlightStylesheet))
        #expect(theme.stylesheet.contains("@media print {\n\(try #require(serif.printStylesheet))\n}"))
        #expect(theme.stylesheet.hasSuffix(css))
        #expect(!theme.stylesheet.contains("#fcfbf8"), "the serif background isn't included")
        #expect(theme.css.contains("body { background: #fdf6e3; }"))
        #expect(theme.css.contains("body { background: #002b36; }"))
    }

    @Test("background-dark defaults to background; neither falls back to the extended theme")
    func backgroundFallbacks() throws {
        let one = try CustomTheme.make(fileName: "a.css", css: "/* mdv-theme\nbackground: #abc\n*/")
        #expect(one.background == ThemeBackground(light: ThemeColor(0xAA_BB_CC), dark: ThemeColor(0xAA_BB_CC)))

        let darkOnly = try CustomTheme.make(fileName: "a.css", css: "/* mdv-theme\nbackground-dark: #111111\n*/")
        #expect(darkOnly.background.light == ThemeRegistry.bundled.defaultTheme.background.light)
        #expect(darkOnly.background.dark == ThemeColor(0x11_11_11))

        let extended = try CustomTheme.make(fileName: "a.css", css: "/* mdv-theme\nextends: document\n*/")
        #expect(extended.background == Theme.document.background)
    }

    @Test("a first comment without the marker is an ordinary comment")
    func commentWithoutMarker() throws {
        let theme = try CustomTheme.make(
            fileName: "license.css", css: "/* Name: Someone Else\n   Background: the story */\np {}")
        #expect(theme.displayName == "license")
    }

    @Test("a header after other CSS is ignored")
    func lateHeader() throws {
        let theme = try CustomTheme.make(fileName: "late.css", css: "p {}\n/* mdv-theme\nname: Late\n*/")
        #expect(theme.displayName == "late")
    }

    @Test(
        "bad header lines are errors with their line",
        arguments: [
            ("/* mdv-theme\nname: A\nbackground: red\n*/", 3),
            ("/* mdv-theme\nbackground: #12345\n*/", 2),
            ("/* mdv-theme\nbackground-dark: #ffffff80\n*/", 2),
            ("/* mdv-theme\nbackground: rgb(0 0 0)\n*/", 2),
            ("/* mdv-theme\nbackgroud: #fff\n*/", 2),
            ("/* mdv-theme\nname: A\nname: B\n*/", 3),
            ("/* mdv-theme\njust some words\n*/", 2),
            ("/* mdv-theme\nname:   \n*/", 2),
            ("/* mdv-theme\nname: \u{202E}\u{0007}\n*/", 2),
            ("\n\n/* mdv-theme\n\nbackground: #zzz\n*/", 5),
        ])
    func badHeader(css: String, line: Int) {
        #expect {
            try CustomTheme.make(fileName: "bad.css", css: css)
        } throws: { error in
            guard case .invalidHeader(let reported, _) = error as? CustomThemeProblem else {
                return false
            }
            return reported == line
        }
    }

    @Test(
        "truncated headers don't crash",
        arguments: ["/*/", "/*", " /* mdv-theme", "/**/", "/* mdv-theme */", "/*mdv-theme*/p{}"])
    func truncatedHeader(css: String) {
        _ = try? CustomTheme.make(fileName: "t.css", css: css)
    }

    @Test("extends must name a bundled theme")
    func unknownBase() {
        #expect(throws: CustomThemeProblem.unknownBaseTheme("custom:other.css")) {
            try CustomTheme.make(fileName: "a.css", css: "/* mdv-theme\nextends: custom:other.css\n*/")
        }
        #expect(throws: CustomThemeProblem.unknownBaseTheme("GitHub")) {
            try CustomTheme.make(fileName: "a.css", css: "/* mdv-theme\nextends: GitHub\n*/")
        }
    }

    @Test("hex colors: #rgb and #rrggbb only")
    func hexColors() {
        #expect(ThemeColor(hex: "#fff") == ThemeColor(0xFF_FF_FF))
        #expect(ThemeColor(hex: "#0D1117") == ThemeColor(0x0D_11_17))
        for bad in ["fff", "#ff", "#ffff", "#fffffff", "#ggg", "#-12", "# fff", "#+ff", "#１２３", "", "#"] {
            #expect(ThemeColor(hex: bad) == nil, "\(bad)")
        }
    }

    @Test("names are cleaned up for menus")
    func sanitizedNames() {
        #expect(CustomTheme.sanitizedName("  Two\n\tLines  ") == "Two Lines")
        #expect(CustomTheme.sanitizedName("evil\u{202E}txt.css") == "evil txt.css")
        #expect(CustomTheme.sanitizedName("\u{0000}\u{200B}") == nil)
        let long = CustomTheme.sanitizedName(String(repeating: "a", count: 500))
        #expect(long?.count == CustomTheme.maximumNameLength)
        #expect(long?.hasSuffix("…") == true)
        #expect(CustomTheme.displayName(forFileName: "\u{2028}.css") == "Untitled Theme")
        #expect(CustomTheme.displayName(forFileName: "dots.in.name.css") == "dots.in.name")
    }

    @Test("a custom theme can't shadow a bundled one")
    func namespacedIDs() throws {
        let theme = try CustomTheme.make(fileName: "github.css", css: "/* mdv-theme\nname: GitHub\n*/")
        #expect(theme.id == "custom:github.css")
        let registry = ThemeRegistry.bundled.adding([theme])
        #expect(registry.theme(id: "github") == .github)
        #expect(registry.pickerSections().last == [theme])
    }

    // MARK: CSS

    @Test(
        "ordinary theme CSS passes",
        arguments: [
            "",
            "p { color: red; }",
            "pre { overflow: auto } @media screen and (prefers-color-scheme: dark) { p { color: #fff } }",
            "body { font-family: \"Avenir Next\", 'Helvetica Neue', sans-serif; }",
            "@font-face { font-family: X; src: local(\"Menlo\"); }",
            "a::after { content: \"}\" \"{\" \")\" \"\\\"\" '/*'; }",
            "/* } { ( url(http://x) @import */ p {}",
            ".sm\\:hidden { display: none; } .\\31 23 {}",
            "p { background: url(data:image/png;base64,iVBORw0KGgo=); }",
            "p { background: url( \"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg'/>\" ); }",
            "p { mask: URL('DATA:IMAGE/gif;base64,R0lGOD==') }",
            "p { background: image-set(url(data:image/png;base64,AA) 1x, \"data:image/png;base64,AA\" 2x); }",
            "p { width: calc((100% - 2em) / 3); } [data-x=\"a\"] {}",
            "@layer mdv-base { p { color: red !important } }",
            "p { content: \"a\\\nb\"; }",
            "p { grid-template-areas: \"a b\" \"c d\"; } q { quotes: \"«\" \"»\"; }",
            "p { color: red } </style><script>alert(1)</script>",
            "@namespace svg \"http://www.w3.org/2000/svg\";",
            "p { font-feature-settings: \"liga\" 1; } img[src$=\"#gh-dark-mode-only\"] {}",
            "p { transition: color 0.2s; width: 2url(x); }",
        ])
    func validCSS(css: String) throws {
        try CustomThemeCSS.validate(css)
    }

    @Test(
        "loads and escapes are rejected",
        arguments: [
            ("@import url(theme2.css);", CustomThemeProblem.importRule(line: 1)),
            ("@import 'x.css';", .importRule(line: 1)),
            ("p {}\n@IMPORT \"x\";", .importRule(line: 2)),
            ("@\\69mport 'x';", .importRule(line: 1)),
            ("@\\000069 mport 'x';", .importRule(line: 1)),
            ("@im\\port 'x';", .importRule(line: 1)),
            ("p { background: url(http://example.com/x.png) }", .externalURL(line: 1)),
            ("p { background: url(https://example.com/x.png) }", .externalURL(line: 1)),
            ("p { background: url(//example.com/x.png) }", .externalURL(line: 1)),
            ("p { background: url(file:///etc/passwd) }", .externalURL(line: 1)),
            ("p { background: url(\"file:///etc/passwd\") }", .externalURL(line: 1)),
            ("p { background: url('x.png') }", .externalURL(line: 1)),
            ("p { background: url(x.png) }", .externalURL(line: 1)),
            ("p { background: url() }", .externalURL(line: 1)),
            ("p { background: url(javascript:alert(1)) }", .externalURL(line: 1)),
            ("p { background: url(mdv-doc://token/x.png) }", .externalURL(line: 1)),
            ("p { background: url(data:text/html,<b>x</b>) }", .externalURL(line: 1)),
            ("@font-face { font-family: X; src: url(data:font/woff2;base64,AA) }", .externalURL(line: 1)),
            ("p { background: URL(http://x) }", .externalURL(line: 1)),
            ("p { background: u\\72l(http://x) }", .externalURL(line: 1)),
            ("p { background: \\75 rl(http://x) }", .externalURL(line: 1)),
            ("p { background: url(\"d\\61ta:image/png,\" \"http://x\") }", .externalURL(line: 1)),
            ("p { background: url(  http://x  ) }", .externalURL(line: 1)),
            ("p { background: url(da\\\nta:image/png,x) }", .externalURL(line: 1)),
            ("p { background: image-set(\"https://x/a.png\" 1x) }", .externalURL(line: 1)),
            ("p { background: -webkit-image-set('a.png' 1x) }", .externalURL(line: 1)),
            ("p { background: image-set(url(http://x) 1x) }", .externalURL(line: 1)),
            ("p { background: image(\"a.png\") }", .externalURL(line: 1)),
            ("p { background: src(\"a.png\") }", .externalURL(line: 1)),
            ("p { background: cross-fade(\"a.png\", 'b.png') }", .externalURL(line: 1)),
            ("\n\np { width: expression(alert(1)) }", .expression(line: 3)),
            ("p { width: EXPRESSION(1) }", .expression(line: 1)),
            ("p { width: expr\\65ssion(1) }", .expression(line: 1)),
        ])
    func rejectedLoads(css: String, problem: CustomThemeProblem) {
        #expect(throws: problem) {
            try CustomThemeCSS.validate(css)
        }
    }

    @Test(
        "brackets, comments, and strings must be closed",
        arguments: [
            (
                "p { color: red; }\n}\n.find-match { display: none !important }",
                CustomThemeProblem.unexpectedClose("}", line: 2)
            ),
            ("}", .unexpectedClose("}", line: 1)),
            ("p { color: red; )", .unexpectedClose(")", line: 1)),
            ("p { width: calc(1px + (2px) }", .unexpectedClose("}", line: 1)),
            ("a[href { }", .unclosed("[", line: 1)),
            ("a[href }", .unexpectedClose("}", line: 1)),
            ("p {\ncolor: red;", .unclosed("{", line: 1)),
            ("p { width: calc(1px }", .unexpectedClose("}", line: 1)),
            ("p { width: calc(1px ", .unclosed("(", line: 1)),
            ("p { background: url(data:image/png,x }", .unclosed("(", line: 1)),
            ("p {}\n/* never closed } ", .unterminatedComment(line: 2)),
            ("p { content: \"open }\n}", .unterminatedString(line: 1)),
            ("p { content: 'open", .unterminatedString(line: 1)),
            ("p { content: \"a\\", .unterminatedString(line: 1)),
            ("p { background: url(data:image/png,a\"b) }", .externalURL(line: 1)),
        ])
    func unbalanced(css: String, problem: CustomThemeProblem) {
        #expect(throws: problem) {
            try CustomThemeCSS.validate(css)
        }
    }

    @Test("a stray close brace in a theme is rejected before it can leave the theme layer")
    func layerEscape() {
        #expect(throws: CustomThemeProblem.unexpectedClose("}", line: 1)) {
            try CustomTheme.make(fileName: "escape.css", css: "} .remote-image { display: none !important } {")
        }
    }

    @Test("</style> stays inside the theme's style element")
    func styleEndTag() throws {
        let theme = try CustomTheme.make(fileName: "x.css", css: "p { color: red } </style><script>alert(1)</script>")
        #expect(!theme.layerCSS.contains("</style"))
        #expect(!theme.layerCSS.contains("</script"))
    }

    @Test("random bytes never crash the checks")
    func fuzz() {
        var generator = SplitMix64(seed: 35)
        let alphabet = Array("{}()[]\"'\\/*@:;urlimportexpression(data:image/ \n\t#é\u{0}")
        for _ in 0..<2000 {
            let length = Int.random(in: 0...200, using: &generator)
            let css = String((0..<length).compactMap { _ in alphabet.randomElement(using: &generator) })
            _ = try? CustomTheme.make(fileName: "fuzz.css", css: css)
        }
    }

    @Test("a large, deeply nested theme is checked quickly")
    func largeInput() throws {
        let nested = String(repeating: "@media screen {", count: 10_000) + String(repeating: "}", count: 10_000)
        try CustomThemeCSS.validate(nested)
        let big = String(repeating: "p { color: red; content: \"x\" } /* c */\n", count: 12_000)
        let start = ContinuousClock.now
        try CustomThemeCSS.validate(big)
        #expect(ContinuousClock.now - start < .seconds(2))
    }
}

/// A seeded generator, so fuzz runs are reproducible.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
