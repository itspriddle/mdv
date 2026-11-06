import Testing

@testable import MdvCore

@Suite("SwiftMarkdownRenderer")
struct MarkdownRendererTests {
    let renderer = SwiftMarkdownRenderer()

    @Test("renders a heading")
    func heading() {
        #expect(renderer.renderBody("# Hello").contains("<h1>Hello</h1>"))
    }

    @Test("renders emphasis inside a paragraph")
    func emphasis() {
        #expect(renderer.renderBody("some *text*") == "<p>some <em>text</em></p>\n")
    }

    @Test("renders GFM tables")
    func table() {
        let html = renderer.renderBody("| a | b |\n|---|---|\n| 1 | 2 |")
        #expect(html.contains("<table>"))
    }
}

@Suite("HTMLDocument")
struct HTMLDocumentTests {
    @Test("wraps body with CSP and stylesheet")
    func wraps() {
        let html = HTMLDocument(title: "Doc", body: "<p>hi</p>", stylesheet: "body{}").html
        #expect(html.contains("Content-Security-Policy"))
        #expect(html.contains("default-src 'none'"))
        #expect(html.contains("<p>hi</p>"))
        #expect(html.contains("body{}"))
    }

    @Test("escapes the title")
    func escapesTitle() {
        let html = HTMLDocument(title: "<script>&", body: "").html
        #expect(html.contains("<title>&lt;script&gt;&amp;</title>"))
    }
}
