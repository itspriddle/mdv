import Testing

@testable import MdvCore

// GitHub gives raw HTML `<h1>`–`<h6>` the same anchors as Markdown headings, slugged from the
// element's text content and de-duplicated together with them; the README corpus (`awesome`,
// `httpie`, `jekyll-front-matter`, `next-js`) checks the ids against github.com.

private func render(_ markdown: String, options: RenderOptions = RenderOptions()) -> RenderedDocument {
    HTMLRenderer(options: options, highlighter: nil).render(markdown)
}

private func anchor(_ slug: String) -> String {
    "<a class=\"anchor\" aria-hidden=\"true\" href=\"#\(slug)\"></a>"
}

@Suite("Raw HTML headings: anchors")
struct RawHTMLHeadingTests {
    @Test("a raw heading gets an id and an anchor link, keeping its attributes")
    func markup() {
        #expect(render("<h2>Raw Title</h2>").html == "<h2 id=\"raw-title\">\(anchor("raw-title"))Raw Title</h2>\n")
        #expect(
            render("<h3 align=\"center\">Centered</h3>").html
                == "<h3 align=\"center\" id=\"centered\">\(anchor("centered"))Centered</h3>\n")
    }

    @Test("every level h1-h6 is anchored; other tags are not")
    func levels() {
        let html = render(
            (1...6).map { "<h\($0)>L\($0)</h\($0)>" }.joined(separator: "\n") + "\n<hr><header>x</header>"
        )
        .html
        for level in 1...6 {
            #expect(html.contains("<h\(level) id=\"l\(level)\">"))
        }
        #expect(!html.contains("<hr id"))
    }

    @Test("slugs come from text content: whitespace, entities, nested tags")
    func slugSource() {
        #expect(render("<h2>A &amp; B &#67;</h2>").headings.map(\.slug) == ["a--b-c"])
        #expect(
            render("<h2><a href=\"https://x.test\">Link</a> <em>text</em></h2>").headings.map(\.slug) == ["link-text"])
        // Tabs and newlines vanish, spaces become `-` (the corpus `awesome` and `httpie` headers).
        #expect(render("<h2>\n\tOne\n\t<br>\n\tTwo three\n</h2>").headings.map(\.slug) == ["onetwo-three"])
    }

    @Test("content the sanitizer drops is not part of the slug")
    func droppedContent() {
        #expect(render("<h2>Safe<script>alert(1)</script><style>x</style></h2>").headings.map(\.slug) == ["safe"])
    }

    @Test("Markdown between a raw start and end tag counts (split HTML blocks)")
    func spansMarkdown() {
        let rendered = render("<h2>\n\nSome *emphasis* and `code`\n\n</h2>")
        #expect(rendered.headings.map(\.slug) == ["some-emphasis-and-code"])
        #expect(rendered.html.hasPrefix("<h2 id=\"some-emphasis-and-code\">\(anchor("some-emphasis-and-code"))\n"))
    }

    @Test("inline raw headings inside a paragraph are anchored")
    func inline() {
        let rendered = render("before <h4>Inline</h4> after")
        #expect(rendered.html.contains("<h4 id=\"inline\">\(anchor("inline"))"))
        #expect(rendered.headings.map(\.slug) == ["inline"])
    }

    @Test("Markdown and raw headings share one de-duplication, in document order")
    func sharedDeduplication() {
        #expect(
            render("# Intro\n\n<h2>Intro</h2>\n\n## Intro").headings.map(\.slug) == ["intro", "intro-1", "intro-2"])
        #expect(render("<h1>Intro</h1>\n\n# Intro").headings.map(\.slug) == ["intro", "intro-1"])
        let html = render("<h1>Intro</h1>\n\n# Intro").html
        #expect(html.contains("<h1 id=\"intro\">"))
        #expect(html.contains("<h1 id=\"intro-1\">"))
    }

    @Test("a raw heading with its own id keeps it; the slug goes on the anchor link")
    func existingID() {
        #expect(
            render("<h2 id=\"custom\">Named</h2>").html
                == "<h2 id=\"user-content-custom\"><a id=\"named\" class=\"anchor\" aria-hidden=\"true\" "
                + "href=\"#named\"></a>Named</h2>\n")
    }

    @Test("raw headings are listed with level, collapsed text, and source line; a raw h1 can title")
    func headingList() {
        let rendered = render("text\n\n<h1 align=\"center\">\nNext.js\n Docs\n</h1>\n\n## After\n")
        #expect(
            rendered.headings == [
                Heading(level: 1, text: "Next.js Docs", slug: "nextjs-docs", sourceLine: 3),
                Heading(level: 2, text: "After", slug: "after", sourceLine: 8),
            ])
        #expect(rendered.title == "Next.js Docs")
    }

    @Test("footnote ids avoid raw heading slugs")
    func footnoteCollision() {
        let html = render("<h2>fn 1</h2>\n\nText[^1].\n\n[^1]: Note.").html
        #expect(html.contains("<h2 id=\"fn-1\">"))
        #expect(html.contains("id=\"fn-1-1\""))
    }

    @Test("image alt text with raw HTML is not a heading")
    func imageAlt() {
        #expect(render("![<h2>alt</h2>](x.png)").headings.isEmpty)
    }

    @Test("anchors off: raw headings stay plain but are still listed")
    func anchorsOff() {
        var options = RenderOptions()
        options.headingAnchors = false
        let rendered = render("<h2>Raw</h2>", options: options)
        #expect(rendered.html == "<h2>Raw</h2>\n")
        #expect(rendered.headings.map(\.slug) == ["raw"])
    }

    @Test("sanitizing off (spec mode): raw HTML is untouched and not collected")
    func specMode() {
        let rendered = render("<h2>Raw</h2>", options: .spec)
        #expect(rendered.html == "<h2>Raw</h2>\n")
        #expect(rendered.headings.isEmpty)
    }

    @Test("a pre-parsed tree's raw headings are anchored too")
    func tree() {
        let tree = MarkdownNode(.document, children: [MarkdownNode(.htmlBlock("<h5>Tree</h5>\n"))])
        #expect(HTMLRenderer(highlighter: nil).html(for: tree).hasPrefix("<h5 id=\"tree\">"))
    }
}
