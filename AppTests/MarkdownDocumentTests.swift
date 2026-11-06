import Testing

@testable import MdvApp

@Suite("MarkdownDocument")
struct MarkdownDocumentTests {
    @Test("renders source into a full HTML document")
    func rendersHTML() {
        let page = MarkdownDocument(source: "Some *text*").renderedPage(fallbackTitle: "README.md")
        #expect(page.html.contains("<p>Some <em>text</em></p>"))
        #expect(page.html.contains("<title>README.md</title>"))
        #expect(page.title == "README.md")
    }

    @Test("uses the first h1 for the window and the page")
    func headingTitle() {
        let page = MarkdownDocument(source: "intro\n\n# Title").renderedPage(fallbackTitle: "README.md")
        #expect(page.html.contains("<h1 id=\"title\">"))
        #expect(page.html.contains("<title>Title</title>"))
        #expect(page.title == "Title")
    }

    @Test("uses the frontmatter title for the window and the page")
    func frontmatterTitle() {
        let page = MarkdownDocument(source: "---\ntitle: Notes & <Ideas>\n---\n# Heading")
            .renderedPage(fallbackTitle: "README.md")
        #expect(page.title == "Notes & <Ideas>")
        #expect(page.html.contains("<title>Notes &amp; &lt;Ideas&gt;</title>"))
        #expect(!page.html.contains("title: Notes"))
    }

    @Test("highlights fenced code at render time, without scripts")
    func highlightsCode() {
        let page = MarkdownDocument(source: "```swift\nlet x = 1\n```").renderedPage(fallbackTitle: "README.md")
        #expect(page.html.contains("<span class=\"hljs-keyword\">let</span>"))
        #expect(!page.html.contains("<script"))
    }
}
