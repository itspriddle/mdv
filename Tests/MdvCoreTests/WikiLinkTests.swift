import Testing

@testable import MdvCore

/// A resolver over a fixed list of files, with the folder resolver's naming rule
/// (`WikiPage.matches`), recording what it was asked.
final class FakeWikiLinkResolver: WikiLinkResolver, @unchecked Sendable {
    let files: [String]
    private(set) var asked: [WikiPage] = []

    init(_ files: [String]) {
        self.files = files
    }

    func destination(for page: WikiPage) -> String? {
        asked.append(page)
        return files.first { path in
            let parts = path.split(separator: "/").map(String.init)
            return page.matches(fileName: parts[parts.count - 1]) && page.matchesFolders(endingWith: parts.dropLast())
        }
    }
}

@Suite("Wiki links")
struct WikiLinkTests {
    static let files = ["Home.md", "Page-Name.md", "guides/Setup.md", "../notes/Other Page.markdown", "a b/c&d.md"]

    static func render(
        _ markdown: String, flavor: Flavor = .gfm, resolver: (any WikiLinkResolver)? = FakeWikiLinkResolver(files)
    ) -> String {
        var options = RenderOptions(flavor: flavor)
        options.builtInPreprocessors = [.wikiLinks]
        return HTMLRenderer(options: options, wikiLinkResolver: resolver).render(markdown).html
    }

    static func link(_ href: String, _ label: String) -> String {
        "<a class=\"wikilink\" href=\"\(href)\">\(label)</a>"
    }

    static func missing(_ label: String) -> String {
        "<a class=\"wikilink wikilink-missing\">\(label)</a>"
    }

    // MARK: - Parsing

    @Test(
        "syntax: page, label, heading, same-document heading",
        arguments: [
            ("[[Home]]", link("Home.md", "Home")),
            ("[[Page Name]]", link("Page-Name.md", "Page Name")),
            ("[[page-name]]", link("Page-Name.md", "page-name")),
            ("[[  PAGE NAME  ]]", link("Page-Name.md", "PAGE NAME")),
            ("[[Home|Start here]]", link("Home.md", "Start here")),
            ("[[Home| ]]", link("Home.md", "Home")),
            ("[[Home|a|b]]", link("Home.md", "a|b")),
            ("[[Home#Getting Started]]", link("Home.md#getting-started", "Home#Getting Started")),
            ("[[Home#Getting Started|go]]", link("Home.md#getting-started", "go")),
            ("[[Home#!!!]]", link("Home.md", "Home#!!!")),
            ("[[#Section Two]]", link("#section-two", "#Section Two")),
            ("[[Home.md]]", link("Home.md", "Home.md")),
            ("[[guides/Setup]]", link("guides/Setup.md", "guides/Setup")),
            ("[[Other Page]]", link("../notes/Other%20Page.markdown", "Other Page")),
            ("[[c&d]]", link("a%20b/c%26d.md", "c&amp;d")),
            ("[[Nope]]", missing("Nope")),
            ("[[../Home]]", missing("../Home")),
            ("[[/Home]]", missing("/Home")),
            ("[[a//b]]", missing("a//b")),
            ("[[Nope#Head]]", missing("Nope#Head")),
        ])
    func syntax(markdown: String, expected: String) {
        #expect(Self.render(markdown) == "<p>\(expected)</p>\n")
    }

    @Test(
        "not wiki links: stays literal",
        arguments: [
            "[[]]", "[[ ]]", "[[#]]", "[[ |label]]", "[[a]b]]", "[[a[b]]", "[[a", "a]]", "[a]]", "[[a]",
            "[[a\nb]]",
        ])
    func literal(markdown: String) {
        let html = Self.render(markdown)
        #expect(!html.contains("wikilink"), "\(markdown): \(html)")
    }

    @Test("several links and surrounding text in one run")
    func several() {
        #expect(
            Self.render("See [[Home]], then [[Nope|x]].")
                == "<p>See \(Self.link("Home.md", "Home")), then \(Self.missing("x")).</p>\n")
        #expect(Self.render("[[[Home]]]") == "<p>[\(Self.link("Home.md", "Home"))]</p>\n")
    }

    @Test("a target over the length limit stays literal")
    func tooLong() {
        let long = String(repeating: "a", count: WikiLinks.maximumTargetBytes + 1)
        #expect(!Self.render("[[\(long)]]").contains("wikilink"))
        let fits = String(repeating: "a", count: WikiLinks.maximumTargetBytes)
        #expect(Self.render("[[\(fits)]]").contains("wikilink-missing"))
    }

    // MARK: - Exclusions

    @Test(
        "never in code, raw HTML, link text, autolinks, alt text, or across markup",
        arguments: [
            "`[[Home]]`",
            "```\n[[Home]]\n```",
            "    [[Home]]",
            "<span title=\"[[Home]]\">x</span>",
            "<div>\n[[Home]]\n</div>",
            "[see [[Home]]](https://example.com)",
            "[[Home]](https://example.com)",
            "<https://example.com/[[Home]]>",
            "https://example.com/[[Home]]",
            "![[[Home]]](x.png)",
            "[[Home *x*]]",
            "[[*Home*]]",
            "[[Home]\n]",
        ])
    func exclusions(markdown: String) {
        let html = Self.render(markdown)
        #expect(!html.contains("wikilink"), "\(markdown): \(html)")
    }

    @Test(
        "escaped or encoded brackets stay literal",
        arguments: [
            "\\[[Home]]", "[\\[Home]]", "[[Home\\]]", "[[Home]\\]", "&#91;[Home]]", "&lbrack;[Home]]",
            "[[Home&#93;]", "> \\[[Home]]", "- \\[[Home]]", "x *y* \\[[Home]]", "a  \nb \\[[Home]]",
        ])
    func escaped(markdown: String) {
        let html = Self.render(markdown)
        #expect(!html.contains("wikilink"), "\(markdown): \(html)")
        #expect(html.contains("[[Home"), "\(markdown): \(html)")
    }

    @Test(
        "found in every context that holds ordinary text",
        arguments: [
            "# [[Home]]", "Title [[Home]]\n===", "> [[Home]]", "> a\n> b [[Home]]", "> a\nlazy [[Home]]",
            "- [[Home]]", "- a\n  b [[Home]]", "1. a\n\tb [[Home]]", "- [ ] [[Home]]", "*[[Home]]*",
            "**[[Home]]**", "~~[[Home]]~~", "a [[Home]]  \nb", "a  \nb [[Home]]", "a\\\nb [[Home]]",
            "x[^1]\n\n[^1]: [[Home]]", "| a |\n|---|\n| [[Home]] |", "| a |\n|---|\n| [[Home\\|x]] |",
            "> [!NOTE]\n> [[Home]]", "a \\* [[Home]]", "&amp; [[Home]] &eacute;é", "é [[Home]]",
            "`code` [[Home]]", "\\[[Home]] [[Home]]",
        ])
    func contexts(markdown: String) {
        let html = Self.render(markdown)
        #expect(html.contains(#"<a class="wikilink" href="Home.md">"#), "\(markdown): \(html)")
    }

    @Test("an escaped and a written link on one line: only the written one links")
    func escapedThenWritten() {
        #expect(
            Self.render("\\[[Home]] [[Home]]") == "<p>[[Home]] \(Self.link("Home.md", "Home"))</p>\n")
        #expect(
            Self.render("| a |\n|---|\n| [[Home\\|x]] |").contains(Self.link("Home.md", "x")))
    }

    @Test("CRLF and CR line endings, and a byte order mark, keep brackets aligned")
    func lineEndings() {
        for markdown in ["a\r\n\\[[Home]] [[Home]]", "a\r\\[[Home]] [[Home]]", "\u{FEFF}\\[[Home]] [[Home]]"] {
            #expect(Self.render(markdown).contains("[[Home]] \(Self.link("Home.md", "Home"))"), "\(markdown)")
        }
    }

    @Test("frontmatter lines count: a link after frontmatter aligns with its own line")
    func afterFrontmatter() {
        #expect(Self.render("---\ntitle: x\n---\n\\[[Home]] [[Home]]").contains("[[Home]] <a class"))
    }

    // MARK: - Escaping

    @Test("labels and targets are escaped; names can't add a scheme, query, or attribute")
    func escaping() {
        let resolver = FakeWikiLinkResolver(["javascript:alert(1).md", "x\"onmouseover=y.md", "q?a#b.md", "%41.md"])
        let html = Self.render(
            """
            [[\\<script>alert(1)\\</script>]] [[a"b|\\<b>"x"\\</b>]] [[javascript:alert(1)]]
            [[x"onmouseover=y]] [[q?a#b]] [[%41]] [[Nope|&lt;i&gt;]] [[#"\\>\\<img src=x\\>]]
            """, resolver: resolver)
        #expect(!html.contains("<script"))
        #expect(!html.contains("<b>"))
        #expect(!html.contains("<img"))
        #expect(!html.contains("<i>"))
        #expect(html.contains(Self.missing("&lt;script&gt;alert(1)&lt;/script&gt;")))
        #expect(html.contains(Self.missing("&lt;b&gt;&quot;x&quot;&lt;/b&gt;")))
        #expect(html.contains(Self.link("javascript%3Aalert%281%29.md", "javascript:alert(1)")))
        #expect(html.contains(Self.link("x%22onmouseover%3Dy.md", "x&quot;onmouseover=y")))
        // `#` starts the heading, so `q?a#b` is page `q?a` (missing here) with heading `b`.
        #expect(html.contains(Self.missing("q?a#b")))
        #expect(html.contains(Self.link("%2541.md", "%41")))
        #expect(html.contains(Self.missing("&lt;i&gt;")))
        #expect(html.contains(Self.link("#img-srcx", "#&quot;&gt;&lt;img src=x&gt;")))
    }

    @Test("emoji shortcodes in labels convert (emoji run after wiki links), not in hrefs")
    func emojiInLabel() {
        let resolver = FakeWikiLinkResolver([":tada:.md"])
        #expect(Self.render("[[:tada:]]", resolver: resolver) == "<p>\(Self.link("%3Atada%3A.md", "🎉"))</p>\n")
        #expect(Self.render("[[:tada:]]", flavor: .commonmark, resolver: resolver).contains(":tada:</a>"))
    }

    // MARK: - Resolution

    @Test("the resolver is asked once per distinct page")
    func askedOnce() {
        let resolver = FakeWikiLinkResolver(Self.files)
        _ = Self.render("[[Home]] [[home]] [[Home|x]] [[Home#a]] [[Nope]] [[Nope]] [[#a]]", resolver: resolver)
        #expect(resolver.asked.map(\.name) == ["Home", "home", "Nope"])
    }

    @Test("without a resolver every page is missing; same-document links still work")
    func noResolver() {
        #expect(
            Self.render("[[Home]] [[#Top]]", resolver: nil)
                == "<p>\(Self.missing("Home")) \(Self.link("#top", "#Top"))</p>\n")
    }

    @Test("the naming rule: spaces as hyphens, any case, Markdown extensions only")
    func naming() throws {
        let page = try #require(WikiPage("Page Name"))
        for name in ["Page-Name.md", "page name.md", "PAGE-NAME.MARKDOWN", "Page Name.mdown", "page-name.mkd"] {
            #expect(page.matches(fileName: name), "\(name)")
        }
        for name in ["Page-Name.txt", "Page-Name", "PageName.md", "Page-Name.md.bak", "Page_Name.md", ".md"] {
            #expect(!page.matches(fileName: name), "\(name)")
        }
        let decomposed = try #require(WikiPage("Cafe\u{301}"))
        #expect(decomposed.matches(fileName: "Caf\u{E9}.md"))
        let exact = try #require(WikiPage("Notes.md"))
        #expect(exact.matches(fileName: "notes.MD"))
        #expect(!exact.matches(fileName: "Notes.md.md"))
        let nested = try #require(WikiPage(" guides / Set up "))
        #expect(nested.folders == ["guides"])
        #expect(nested.fileName == "Set up")
        #expect(nested.matchesFolders(endingWith: ["docs", "Guides"]))
        #expect(!nested.matchesFolders(endingWith: ["docs"]))
        for invalid in [
            "", " ", "/x", "x/", "a//b", "./x", "../x", "a/../b", "a\u{0}b", "a\u{7}b",
            String(repeating: "x", count: 256),
        ] {
            #expect(WikiPage(invalid) == nil, "\(invalid.debugDescription)")
        }
        #expect(WikiPage(Array(repeating: "a", count: WikiPage.maximumParts).joined(separator: "/")) != nil)
        #expect(WikiPage(Array(repeating: "a", count: WikiPage.maximumParts + 1).joined(separator: "/")) == nil)
    }

    // MARK: - Off by default

    @Test("off by default: output unchanged, in every flavor")
    func offByDefault() {
        #expect(RenderOptions().builtInPreprocessors.isEmpty)
        #expect(!RenderOptions().transforms.contains(.wikiLinks))
        let markdown = "[[Home]] [[Page Name|x]] [[#Top]] \\[[Home]]"
        for flavor in FlavorRegistry.bundled.flavors {
            let html = HTMLRenderer(
                options: RenderOptions(flavor: flavor), wikiLinkResolver: FakeWikiLinkResolver(Self.files)
            )
            .render(markdown).html
            #expect(html == "<p>[[Home]] [[Page Name|x]] [[#Top]] [[Home]]</p>\n")
        }
        #expect(RenderOptions.spec.builtInPreprocessors.isEmpty)
    }

    @Test("works in CommonMark too, independent of the flavor")
    func commonMark() {
        #expect(Self.render("[[Home]]", flavor: .commonmark) == "<p>\(Self.link("Home.md", "Home"))</p>\n")
    }
}

// MARK: - Tree, headings, source lines

extension WikiLinkTests {
    @Test("a wiki link in a heading: label in the heading text and slug")
    func inHeading() {
        var options = RenderOptions()
        options.builtInPreprocessors = [.wikiLinks]
        let rendered = HTMLRenderer(options: options, wikiLinkResolver: FakeWikiLinkResolver(Self.files))
            .render("# See [[Home|the start]]")
        #expect(rendered.headings.map(\.text) == ["See the start"])
        #expect(rendered.headings.map(\.slug) == ["see-the-start"])
        #expect(rendered.title == "See the start")
    }

    @Test("new nodes keep the source range of the text they replace")
    func sourceRanges() {
        var options = RenderOptions()
        options.builtInPreprocessors = [.wikiLinks]
        options.sourceLines = true
        let html = HTMLRenderer(options: options, wikiLinkResolver: FakeWikiLinkResolver(Self.files))
            .render("intro\n\nsee [[Home]]\n").html
        let paragraph = "<p data-source-line=\"3\">see \(Self.link("Home.md", "Home"))</p>\n"
        #expect(html == "<p data-source-line=\"1\">intro</p>\n" + paragraph)
    }

    @Test("html(for:) on a tree without source text takes brackets as written")
    func treeWithoutSource() {
        var options = RenderOptions()
        options.builtInPreprocessors = [.wikiLinks]
        let tree = MarkdownNode(
            .document, children: [MarkdownNode(.paragraph, children: [MarkdownNode(.text("[[Home]]"))])])
        #expect(
            HTMLRenderer(options: options, wikiLinkResolver: FakeWikiLinkResolver(Self.files)).html(for: tree)
                == "<p>\(Self.link("Home.md", "Home"))</p>\n")
    }

    @Test("pathological input stays bounded")
    func pathological() {
        let brackets = String(repeating: "[[", count: 20_000) + String(repeating: "]]", count: 20_000)
        _ = Self.render(brackets)
        let many = String(repeating: "[[Home]] \\[[x]] ", count: 5_000)
        #expect(Self.render(many).components(separatedBy: "class=\"wikilink\"").count == 5_001)
        let longLine = String(repeating: "&amp;", count: 3_000) + " \\[[Home]]"
        #expect(!Self.render(longLine).contains("wikilink"))
    }
}
