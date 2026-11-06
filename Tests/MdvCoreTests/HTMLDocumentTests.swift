import Testing

@testable import MdvCore

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
