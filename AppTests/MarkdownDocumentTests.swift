import Testing

@testable import MdvApp

@Suite("MarkdownDocument")
struct MarkdownDocumentTests {
    @Test("renders source into a full HTML document")
    func rendersHTML() {
        let html = MarkdownDocument(source: "# Title").renderedHTML(title: "README.md")
        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<title>README.md</title>"))
    }
}
