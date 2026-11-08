import Foundation
import MdvCore
import Testing

@testable import MdvApp

@Suite("DocumentContent")
struct DocumentContentTests {
    @Test("renders source into a full HTML document")
    func rendersHTML() {
        let page = DocumentContent(source: "Some *text*", fallbackTitle: "README.md").page
        #expect(page.html(theme: .github).contains("<p data-source-line=\"1\">Some <em>text</em></p>"))
        #expect(page.html(theme: .github).contains("<title>README.md</title>"))
        #expect(page.title == "README.md")
    }

    @Test("uses the first h1 for the window and the page")
    func headingTitle() {
        let page = DocumentContent(source: "intro\n\n# Title", fallbackTitle: "README.md").page
        #expect(page.html(theme: .github).contains("<h1 id=\"title\" data-source-line=\"3\">"))
        #expect(page.html(theme: .github).contains("<title>Title</title>"))
        #expect(page.title == "Title")
    }

    @Test("uses the frontmatter title for the window and the page")
    func frontmatterTitle() {
        let page = DocumentContent(source: "---\ntitle: Notes & <Ideas>\n---\n# Heading", fallbackTitle: "README.md")
            .page
        #expect(page.title == "Notes & <Ideas>")
        #expect(page.html(theme: .github).contains("<title>Notes &amp; &lt;Ideas&gt;</title>"))
        #expect(!page.html(theme: .github).contains("title: Notes"))
        #expect(page.html(theme: .github).contains("<h1 id=\"heading\" data-source-line=\"4\">"))
    }

    @Test("the page is put together with the window's theme")
    func pageTheme() {
        let page = DocumentContent(source: "Some *text*", fallbackTitle: "README.md").page
        #expect(page.html(theme: .serif).contains(Theme.serif.layerCSS))
        #expect(!page.html(theme: .serif).contains(Theme.github.layerCSS))
        #expect(page.html(theme: .github).contains(Theme.github.layerCSS))
    }

    @Test("highlights fenced code at render time, without scripts")
    func highlightsCode() {
        let page = DocumentContent(source: "```swift\nlet x = 1\n```", fallbackTitle: "README.md").page
        #expect(page.html(theme: .github).contains("<span class=\"hljs-keyword\">let</span>"))
        #expect(!page.html(theme: .github).contains("<script"))
    }

    @Test("keeps the body fragment and headings for in-place swaps and the outline")
    func bodyAndHeadings() {
        let page = DocumentContent(source: "# One\n\n## Two", fallbackTitle: "README.md").page
        #expect(page.body.hasPrefix("<h1 id=\"one\" data-source-line=\"1\">"))
        #expect(!page.body.contains("<article"))
        #expect(page.headings.map(\.slug) == ["one", "two"])
        #expect(page.headings.map(\.sourceLine) == [1, 3])
    }

    @Test("renders GFM by default and the given flavor otherwise")
    func flavor() {
        let source = "| a |\n| - |\n\n:tada:"
        let gfm = DocumentContent(source: source, fallbackTitle: "a.md").page.body
        #expect(gfm.contains("<table data-source-line=\"1\">"))
        #expect(gfm.contains("🎉"))
        let commonmark = DocumentContent(source: source, fallbackTitle: "a.md", flavor: .commonmark).page.body
        #expect(!commonmark.contains("<table"))
        #expect(commonmark.contains("<p data-source-line=\"4\">:tada:</p>"))
        #expect(DocumentContent.renderOptions().flavor == .gfm)
        #expect(DocumentPasteboard.copyableHTML(for: source, flavor: .commonmark).contains("| a |"))
    }

    @Test("decodes UTF-8 and rejects other encodings")
    func decoding() throws {
        let content = try DocumentContent(data: Data("caf\u{E9}".utf8), fallbackTitle: "a.md")
        #expect(content.source == "caf\u{E9}")
        #expect(throws: CocoaError.self) {
            try DocumentContent(data: Data([0x63, 0xE9, 0xFF]), fallbackTitle: "a.md")
        }
    }
}
