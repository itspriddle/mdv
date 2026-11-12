import Foundation
import Testing

@testable import PeepCore

@Suite("RootRelativeURL")
struct RootRelativeURLTests {
    static let root = "/Users/me/repo"

    @Test(
        "resolves root-relative URLs against the root, clamping dot segments at it",
        arguments: [
            ("/docs/x.png", "/Users/me/repo/docs/x.png"),
            ("/", "/Users/me/repo/"),
            ("/docs/", "/Users/me/repo/docs/"),
            ("/docs/x.png?v=1#gh-dark-mode-only", "/Users/me/repo/docs/x.png?v=1#gh-dark-mode-only"),
            ("/docs/./a/../x.png", "/Users/me/repo/docs/x.png"),
            ("/../x.png", "/Users/me/repo/x.png"),
            ("/../../../etc/passwd", "/Users/me/repo/etc/passwd"),
            ("/docs/..", "/Users/me/repo/"),
            ("/docs/.", "/Users/me/repo/docs/"),
            ("/%2e%2e/x.png", "/Users/me/repo/x.png"),
            ("/.%2E/%2e./x.png", "/Users/me/repo/x.png"),
            ("/%2E/x.png", "/Users/me/repo/x.png"),
            ("/docs/../?q=/../x", "/Users/me/repo/?q=/../x"),
            ("/a#/../../x", "/Users/me/repo/a#/../../x"),
            // Other encoded segments are kept; `DocumentURLScheme` refuses `%2f` and `%00`.
            ("/docs%2f..%2fx.png", "/Users/me/repo/docs%2f..%2fx.png"),
            ("/with%20space.png", "/Users/me/repo/with%20space.png"),
            ("/a//b.png", "/Users/me/repo/a//b.png"),
            // Cleaned as a URL parser does.
            ("  /docs/x.png\n", "/Users/me/repo/docs/x.png"),
            ("/do\tcs/x.png", "/Users/me/repo/docs/x.png"),
        ])
    func resolves(url: String, expected: String) {
        #expect(RootRelativeURL.resolve(url, root: Self.root) == expected)
    }

    @Test(
        "leaves everything else alone",
        arguments: [
            "//example.com/x.png", "/\\example.com/x.png", "/\t/example.com/x.png", "\n//example.com",
            "x.png", "./x.png", "../x.png", "#top", "?q", "", "https://example.com/x.png", "mailto:a@b.c",
            "data:image/png;base64,AAAA",
        ])
    func unchanged(url: String) {
        #expect(RootRelativeURL.resolve(url, root: Self.root) == nil)
    }

    @Test("percent-encodes the root, including %, and handles / as the root")
    func encodesRoot() {
        #expect(
            RootRelativeURL.resolve("/x.png", root: "/Users/me/100% my repo") == "/Users/me/100%25%20my%20repo/x.png")
        #expect(RootRelativeURL.resolve("/x.png", root: "/Users/me/caf\u{E9}") == "/Users/me/caf%C3%A9/x.png")
        #expect(RootRelativeURL.resolve("/../x.png", root: "/") == "/x.png")
        // Never scheme-relative, even after dot segments are removed.
        #expect(RootRelativeURL.resolve("/.//evil.example/x.png", root: "/") == "/evil.example/x.png")
        #expect(RootRelativeURL.resolve("/..//evil.example/x.png", root: "/") == "/evil.example/x.png")
        #expect(RootRelativeURL.resolve("/a/..//evil.example", root: "/") == "/evil.example")
        #expect(
            RootRelativeURL.resolve("/.//evil.example/x.png", root: Self.root) == "/Users/me/repo/evil.example/x.png")
        #expect(RootRelativeURL.resolve("/x.png", root: "relative") == nil)
    }

    @Test("a resolved URL maps back, through the page URL, to the file under the root")
    func mapsToFile() throws {
        let token = "token"
        let page = try #require(DocumentURLScheme.url(token: token, filePath: "/Users/me/repo/docs/guide/README.md"))
        for (url, expected) in [
            ("/docs/x.png", "/Users/me/repo/docs/x.png"), ("/../../x.png", "/Users/me/repo/x.png"),
            ("/a%20b.png#gh-light-mode-only", "/Users/me/repo/a b.png"),
        ] {
            let resolved = try #require(RootRelativeURL.resolve(url, root: Self.root))
            let absolute = try #require(URL(string: resolved, relativeTo: page)?.absoluteURL)
            #expect(DocumentURLScheme.filePath(from: absolute, token: token) == expected, "\(url)")
        }
        let encodedSlash = try #require(RootRelativeURL.resolve("/docs%2fx.png", root: Self.root))
        let absolute = try #require(URL(string: encodedSlash, relativeTo: page)?.absoluteURL)
        #expect(DocumentURLScheme.filePath(from: absolute, token: token) == nil)
    }
}

@Suite("Root-relative rendering")
struct RootRelativeRenderingTests {
    static func render(_ markdown: String, linkRoot: String? = "/r/my repo") -> String {
        var options = RenderOptions()
        options.linkRoot = linkRoot
        options.headingAnchors = false
        return HTMLRenderer(options: options, highlighter: nil).render(markdown).html
    }

    @Test("Markdown images and links resolve against linkRoot")
    func markdown() {
        let html = Self.render("![a](/docs/a.png \"T\") [b](/docs/b.md#x) [c](c.md) ![d](//cdn.example/d.png)")
        #expect(html.contains(#"<img src="/r/my%20repo/docs/a.png" alt="a" title="T" />"#))
        #expect(html.contains(#"<a href="/r/my%20repo/docs/b.md#x">b</a>"#))
        #expect(html.contains(#"<a href="c.md">c</a>"#))
        #expect(html.contains(#"<img src="//cdn.example/d.png" alt="d" />"#))
    }

    @Test("raw HTML img src, a href, and source srcset resolve against linkRoot")
    func rawHTML() {
        let html = Self.render(
            """
            <picture><source media="(prefers-color-scheme: dark)" srcset="/d.png 1x, /d@2x.png 2x,x.png">\
            <img src="&#x2F;l.png" alt="x"></picture>

            <a href="/docs/&quot;q&quot;.md?a=1&amp;b=2">doc</a> <img src="//h.example/x.png"> <img src="rel.png">
            """)
        let srcset = "/r/my%20repo/d.png 1x, /r/my%20repo/d@2x.png 2x,x.png"
        #expect(html.contains(#"<source media="(prefers-color-scheme: dark)" srcset="\#(srcset)">"#), "\(html)")
        #expect(html.contains(#"<img src="/r/my%20repo/l.png" alt="x">"#), "\(html)")
        #expect(html.contains(#"<a href="/r/my%20repo/docs/%22q%22.md?a=1&amp;b=2">doc</a>"#), "\(html)")
        #expect(html.contains(#"<img src="//h.example/x.png">"#))
        #expect(html.contains(#"<img src="rel.png">"#))
    }

    @Test("named character references in raw HTML URLs are decoded before encoding (#43)")
    func namedReferences() {
        let html = Self.render(
            """
            <img src="/docs/caf&eacute;.png"> <a href="/na&iuml;ve.md#x&amp;y">n</a> \
            <img src="/a&nbsp;b.png"> <img src="/c&eacute.png"> <img src="/d&eacute=x.png"> \
            <img src="/not&notanentity;.png">

            <picture><source srcset="/x&eacute;&nbsp;y.png 2x"><img src="x.png"></picture>
            """)
        #expect(html.contains(#"<img src="/r/my%20repo/docs/caf%C3%A9.png">"#), "\(html)")
        #expect(html.contains(#"<a href="/r/my%20repo/na%C3%AFve.md#x&amp;y">n</a>"#), "\(html)")
        #expect(html.contains(#"<img src="/r/my%20repo/a%C2%A0b.png">"#), "\(html)")
        // Legacy references decode without `;`, except before `=` in an attribute.
        #expect(html.contains(#"<img src="/r/my%20repo/c%C3%A9.png">"#), "\(html)")
        #expect(html.contains(#"<img src="/r/my%20repo/d&amp;eacute=x.png">"#), "\(html)")
        #expect(html.contains(#"<img src="/r/my%20repo/not&amp;notanentity;.png">"#), "\(html)")
        // `&nbsp;` is not srcset whitespace: it stays in the URL.
        #expect(html.contains(#"<source srcset="/r/my%20repo/x%C3%A9%C2%A0y.png 2x">"#), "\(html)")
    }

    @Test("references outside rewritten URLs are kept as written")
    func referencesKept() {
        // `&notit;` is `&not` followed by an alphanumeric: not a reference in an attribute.
        let value = AttributeValue("caf&eacute; &eacute &notin; &notit; &amp;eacute; &#233;")
        #expect(value.serialized == "caf&eacute; &eacute &notin; &notit; &amp;eacute; &#xE9;")
        #expect(value.decoded == "caf&eacute; &eacute &notin; &notit; &eacute; \u{E9}")
        #expect(value.text == "caf\u{E9} \u{E9} \u{2209} &notit; &eacute; \u{E9}")
        #expect(Self.render(#"<img src="caf&eacute;.png">"#).contains(#"<img src="caf&eacute;.png">"#))
    }

    @Test("without linkRoot (peep --html, spec mode) nothing changes")
    func off() {
        let html = Self.render("![a](/docs/a.png) <img src=\"/b.png\">", linkRoot: nil)
        #expect(html.contains(#"<img src="/docs/a.png" alt="a" />"#))
        #expect(html.contains(#"<img src="/b.png">"#))
        #expect(RenderOptions().linkRoot == nil)
        #expect(RenderOptions.spec.linkRoot == nil)
    }

    @Test("srcset splitting keeps every character and finds each URL")
    func srcsetSplit() {
        let srcset = " a.png 1x,b.png,, c(1).png 100w (x, y), d.png"
        let pieces = SrcsetCandidates.split(srcset)
        #expect(pieces.map(\.text).joined() == srcset)
        #expect(pieces.filter(\.isURL).map(\.text) == ["a.png", "b.png", "c(1).png", "d.png"])
    }
}

@Suite("Light and dark mode images")
struct ColorModeImageTests {
    @Test("recognizes GitHub's exact, case-sensitive fragments")
    func fragments() {
        #expect(ColorModeImage(source: "x.png#gh-dark-mode-only") == .dark)
        #expect(ColorModeImage(source: "https://a.example/x.png#gh-light-mode-only") == .light)
        #expect(ColorModeImage(source: "x.png#GH-DARK-MODE-ONLY") == nil)
        #expect(ColorModeImage(source: "x.png#gh-dark-mode-only?x") == nil)
        #expect(ColorModeImage(source: "x.png") == nil)
    }

    @Test("the base layer hides the other appearance's images and placeholders; print counts as light")
    func css() throws {
        let css = ThemeBase.css
        let lightBlock = try #require(css.range(of: "@media not screen and (prefers-color-scheme: dark) {"))
        let lightRules = css[lightBlock.upperBound...].prefix { $0 != "}" }
        #expect(lightRules.contains(##"img[src$="#gh-dark-mode-only"], .remote-image.gh-dark-mode-only"##))
        #expect(lightRules.contains("display: none !important;"))
        let darkStart = try #require(
            css.range(of: #"@media screen and (prefers-color-scheme: dark) {"#, options: .backwards))
        let darkRules = css[darkStart.upperBound...].prefix { $0 != "}" }
        #expect(darkRules.contains(##"img[src$="#gh-light-mode-only"], .remote-image.gh-light-mode-only"##))
    }

    @Test("blocked remote placeholders carry the variant as a class")
    func placeholders() {
        var options = RenderOptions()
        options.remoteImages = .block
        let html = HTMLRenderer(options: options, highlighter: nil).render(
            """
            ![d](https://a.example/d.png#gh-dark-mode-only) <img alt="l" src="https://a.example/l.png#gh-light-mode-only">
            ![n](https://a.example/n.png)
            """
        ).html
        #expect(html.contains(#"<span class="remote-image gh-dark-mode-only" role="img""#))
        #expect(html.contains(#"<span class="remote-image gh-light-mode-only" role="img""#))
        #expect(html.contains(#"<span class="remote-image" role="img" aria-label="Blocked remote image: n"#))
    }

    @Test("local images keep the fragment in src, and the policy ignores it")
    func localFragment() throws {
        let html = HTMLRenderer(highlighter: nil).render("![d](img/d.png#gh-dark-mode-only)").html
        #expect(html.contains(#"src="img/d.png#gh-dark-mode-only""#))
        let url = try #require(URL(string: "peep-doc://t/r/img/d.png#gh-dark-mode-only"))
        #expect(DocumentURLScheme.filePath(from: url, token: "t") == "/r/img/d.png")
    }
}
