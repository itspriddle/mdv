import Foundation
import Testing

@testable import MdvCore

@Suite("RemoteImage")
struct RemoteImageTests {
    @Test(
        "classifies remote sources and extracts the host",
        arguments: [
            ("https://img.shields.io/badge/x.svg", "img.shields.io", true),
            ("HTTPS://Example.COM/a.png", "example.com", true),
            ("http://example.com:8080/a.png", "example.com:8080", false),
            ("https://user:pw@example.com/a.png", "example.com", true),
            ("https:example.com/a.png", "example.com", true),
            ("https:\\\\example.com\\a.png", "example.com", true),
            ("//cdn.example.com/a.png", "cdn.example.com", false),
            ("\\\\cdn.example.com/a.png", "cdn.example.com", false),
            ("ht\ttps://example.com/a.png", "example.com", true),
            (" https://example.com?x", "example.com", true),
            ("ftp://example.com/a.png", "example.com", false),
            ("https://", "", true),
        ])
    func remote(source: String, host: String, isHTTPS: Bool) throws {
        let image = try #require(RemoteImage(source: source))
        #expect(image.url == source)
        #expect(image.host == host)
        #expect(image.isHTTPS == isHTTPS)
    }

    @Test(
        "relative paths and data: URLs are local",
        arguments: [
            "a.png", "./img/a.png", "../a.png", "/abs/a.png", "#frag", "?q", "", "a b:c.png", "/x:y.png", "1http://x",
            "data:image/png;base64,AAAA", "DATA:image/gif,x", "-x:y",
        ])
    func local(source: String) {
        #expect(RemoteImage(source: source) == nil)
    }

    @Test("policies decide which remote images become placeholders")
    func policies() throws {
        let https = try #require(RemoteImage(source: "https://a.example/x.png"))
        let http = try #require(RemoteImage(source: "http://a.example/x.png"))
        let relative = try #require(RemoteImage(source: "//a.example/x.png"))
        #expect(!RemoteImagePolicy.keep.blocks(https) && !RemoteImagePolicy.keep.blocks(http))
        #expect(RemoteImagePolicy.block.blocks(https) && RemoteImagePolicy.block.blocks(http))
        #expect(!RemoteImagePolicy.allowHTTPS.blocks(https))
        #expect(RemoteImagePolicy.allowHTTPS.blocks(http))
        #expect(RemoteImagePolicy.allowHTTPS.blocks(relative))
    }

    @Test(
        "placeholder sizes copy plain numeric lengths only",
        arguments: [
            ("20", "20px"), (" 20px ", "20px"), ("20PX", "20px"), ("50%", "50%"), ("250%", "100%"),
            ("999999", "10000px"),
        ])
    func lengths(attribute: String, css: String) {
        #expect(RemoteImagePlaceholder.Length(attribute)?.css == css)
    }

    @Test(
        "placeholder sizes ignore anything else",
        arguments: ["", "0", "-5", "1.5", "20em", "calc(1px)", "1;color:red", "expression(x)", "1234567"])
    func badLengths(attribute: String) {
        #expect(RemoteImagePlaceholder.Length(attribute) == nil)
    }
}

@Suite("Remote images in rendered output")
struct RemoteImageRenderingTests {
    static func render(_ markdown: String, _ policy: RemoteImagePolicy) -> RenderedDocument {
        var options = RenderOptions()
        options.remoteImages = policy
        return HTMLRenderer(options: options, highlighter: nil).render(markdown)
    }

    /// Every `src`/`srcset` value in `html`.
    static func sources(in html: String) -> [String] {
        html.matches(of: /(?:src|srcset)="([^"]*)"/).map { String($0.1) }
    }

    static let mixed = """
        ![Build](https://img.shields.io/build.svg) ![Plain](http://example.com/p.png)
        ![Local](img/a.png) ![Data](data:image/png;base64,AAAA) ![Scheme-relative](//cdn.example/x.png)

        <img src="https://raw.example/r.png" alt="Raw &amp; &eacute;" width="40" height="20px">
        <img src="http://raw.example/c.png" width="1;color:red">

        <picture><source srcset="https://raw.example/wide.png 2x"><img src="img/narrow.png" alt="Narrow"></picture>
        """

    @Test("by default (and for mdv --html) remote images are kept, as on GitHub")
    func keepIsDefault() {
        #expect(RenderOptions().remoteImages == .keep)
        #expect(RenderOptions.spec.remoteImages == .keep)
        let rendered = HTMLRenderer(highlighter: nil).render(Self.mixed)
        #expect(rendered.blockedRemoteImages.isEmpty)
        #expect(!rendered.html.contains("remote-image"))
        #expect(
            Self.sources(in: rendered.html) == [
                "https://img.shields.io/build.svg", "http://example.com/p.png", "img/a.png",
                "data:image/png;base64,AAAA", "//cdn.example/x.png", "https://raw.example/r.png",
                "http://raw.example/c.png", "https://raw.example/wide.png 2x", "img/narrow.png",
            ])
    }

    @Test("blocking replaces every remote image and keeps local ones")
    func block() {
        let rendered = Self.render(Self.mixed, .block)
        #expect(Self.sources(in: rendered.html) == ["img/a.png", "data:image/png;base64,AAAA", "img/narrow.png"])
        #expect(
            rendered.blockedRemoteImages.map(\.url) == [
                "https://img.shields.io/build.svg", "http://example.com/p.png", "//cdn.example/x.png",
                "https://raw.example/r.png", "http://raw.example/c.png", "https://raw.example/wide.png",
            ])
        #expect(
            rendered.html.contains(
                """
                <span class="remote-image" role="img" aria-label="Blocked remote image: Build (img.shields.io)" \
                title="https://img.shields.io/build.svg"><span class="remote-image-alt">Build</span>\
                <span class="remote-image-host">img.shields.io</span></span>
                """))
        // Raw HTML: alt keeps its references, the size is copied, a bad size is dropped.
        #expect(
            rendered.html.contains(
                """
                aria-label="Blocked remote image: Raw &amp; &eacute; (raw.example)" \
                title="https://raw.example/r.png" style="width: 40px; height: 20px">
                """))
        #expect(
            rendered.html.contains(
                "aria-label=\"Blocked remote image: Image (raw.example)\" title=\"http://raw.example/c.png\">"))
        #expect(!rendered.html.contains("color:red"))
        // The <source> is gone; the picture falls back to its local <img>.
        #expect(rendered.html.contains("<picture><img src=\"img/narrow.png\" alt=\"Narrow\"></picture>"))
    }

    @Test("after opting in, https images load and the rest stay placeholders")
    func allowHTTPS() {
        let rendered = Self.render(Self.mixed, .allowHTTPS)
        #expect(
            Self.sources(in: rendered.html) == [
                "https://img.shields.io/build.svg", "img/a.png", "data:image/png;base64,AAAA",
                "https://raw.example/r.png", "https://raw.example/wide.png 2x", "img/narrow.png",
            ])
        #expect(
            rendered.blockedRemoteImages.map(\.url) == [
                "http://example.com/p.png", "//cdn.example/x.png", "http://raw.example/c.png",
            ])
        #expect(rendered.blockedRemoteImages.allSatisfy { !$0.isHTTPS })
    }

    @Test("a picture with blocked images is reported once, also when only a source is remote (#43)")
    func pictureSources() {
        let rendered = Self.render(
            """
            <picture><source media="(prefers-color-scheme: dark)" srcset="local.png 1x, http://a.example/d.png 2x">\
            <source srcset="https://b.example/w.png"><img src="https://c.example/i.png"></picture>

            <picture>
            <source srcset="https://d.example/only.png">
            <img src="local.png">
            </picture>

            <source srcset="https://e.example/stray.png">
            """, .block)
        #expect(rendered.blockedRemoteImages.map(\.url) == ["http://a.example/d.png", "https://d.example/only.png"])
        #expect(Self.sources(in: rendered.html) == ["local.png"])
        let optedIn = Self.render("<picture><source srcset=\"https://d.example/only.png\"><img src=\"x.png\"></picture>", .allowHTTPS)
        #expect(optedIn.blockedRemoteImages.isEmpty)
    }

    @Test("a blocked image inside a link stays inside the link")
    func linkedBadge() {
        let html = Self.render("[![CI](https://ci.example/badge.svg)](https://ci.example)", .block).html
        #expect(html.hasPrefix("<p><a href=\"https://ci.example\"><span class=\"remote-image\""))
        #expect(html.hasSuffix("</span></a></p>\n"))
    }

    @Test("alt text and URLs in placeholders are escaped")
    func escaping() {
        let html = Self.render(#"![<b>"x"</b> & 'y'](https://a.example/"><script>.png)"#, .block).html
        #expect(!html.contains("<script"))
        #expect(!html.contains("<b>"))
        #expect(html.contains("Blocked remote image: &lt;b&gt;&quot;x&quot;&lt;/b&gt; &amp; &#39;y&#39;"))
        #expect(OutputChecker.problems(in: html, isMarkdown: true).filter { $0 != "attribute style" }.isEmpty)
    }

    @Test("raw HTML image sources are judged after decoding character references")
    func encodedRawSource() {
        let rendered = Self.render(#"<img src="h&#116;tps&#x3a;//e.example/x.png">"#, .block)
        #expect(rendered.blockedRemoteImages.map(\.host) == ["e.example"])
        #expect(Self.sources(in: rendered.html).isEmpty)
    }

    @Test("file: and other safe-mode-blanked images are not remote")
    func dangerous() {
        let rendered = Self.render("![f](file:///etc/x.png) ![j](javascript:x)", .block)
        #expect(rendered.blockedRemoteImages.isEmpty)
        #expect(rendered.html == "<p><img src=\"\" alt=\"f\" /> <img src=\"\" alt=\"j\" /></p>\n")
    }

    @Test("images in dropped raw HTML or alt text are neither rendered nor reported")
    func dropped() {
        let rendered = Self.render(
            "<script>![a](https://a.example/a.png)</script> ![outer ![inner](https://i.example/i.png)](x.png)", .block)
        #expect(rendered.blockedRemoteImages.isEmpty)
    }

    @Test("blocked output has no remote URL in any loading attribute, for the XSS corpus too")
    func noRemoteSourcesInCorpus() {
        let documents = xssCorpus + [Self.mixed]
        for document in documents {
            let html = Self.render(document, .block).html
            for source in Self.sources(in: html) {
                #expect(RemoteImage(source: source) == nil || source.hasPrefix("data:"), "\(document) -> \(source)")
            }
        }
    }
}

@Suite("ContentSecurityPolicy (remote images)")
struct RemoteImageContentSecurityPolicyTests {
    @Test("opting in adds https: images only")
    func viewerAllowingRemoteImages() {
        #expect(
            ContentSecurityPolicy.viewerAllowingRemoteImages.header
                == "default-src 'none'; style-src 'unsafe-inline'; img-src mdv-doc: data: https:;")
        #expect(!ContentSecurityPolicy.viewerAllowingRemoteImages.header.contains("http:"))
        #expect(!ContentSecurityPolicy.viewerAllowingRemoteImages.header.contains("*"))
    }

    @Test("the default viewer and standalone policies allow no remote images")
    func blockedByDefault() {
        for policy in [ContentSecurityPolicy.viewer, .standalone] {
            #expect(!policy.header.contains("http"))
            #expect(policy.header.hasPrefix("default-src 'none';"))
        }
    }
}
