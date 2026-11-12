import Testing

@testable import MdvCore

@Suite("HTMLDocument")
struct HTMLDocumentTests {
    @Test("wraps body with CSP and the theme")
    func wraps() {
        let theme = Theme(
            id: "t", displayName: "T", background: Theme.github.background, stylesheet: "body{}")
        let html = HTMLDocument(title: "Doc", body: "<p>hi</p>", theme: theme).html
        #expect(html.contains("Content-Security-Policy"))
        #expect(html.contains("default-src 'none'"))
        #expect(html.contains("<p>hi</p>"))
        #expect(html.contains("body{}"))
    }

    @Test("escapes the title")
    func escapesTitle() {
        let html = HTMLDocument(title: "<script>&", body: "", theme: .github).html
        #expect(html.contains("<title>&lt;script&gt;&amp;</title>"))
    }
}
