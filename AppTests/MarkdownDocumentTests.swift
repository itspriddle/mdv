import Testing

@testable import MdvApp

@Suite("MarkdownDocument")
struct MarkdownDocumentTests {
    @Test("renders source into a full HTML document")
    func rendersHTML() {
        let page = MarkdownDocument(source: "# Title").renderedPage(fallbackTitle: "README.md")
        #expect(page.html.contains("<h1>Title</h1>"))
        #expect(page.html.contains("<title>README.md</title>"))
        #expect(page.title == "README.md")
    }

    @Test("uses the frontmatter title for the window and the page")
    func frontmatterTitle() {
        let page = MarkdownDocument(source: "---\ntitle: Notes & <Ideas>\n---\n# Heading")
            .renderedPage(fallbackTitle: "README.md")
        #expect(page.title == "Notes & <Ideas>")
        #expect(page.html.contains("<title>Notes &amp; &lt;Ideas&gt;</title>"))
        #expect(!page.html.contains("title: Notes"))
    }
}
