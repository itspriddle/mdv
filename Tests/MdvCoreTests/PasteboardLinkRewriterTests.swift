import Foundation
import Testing

@testable import MdvCore

private let token = "0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0"
private let documentLink = "mdv-doc://\(token)/Users/me/docs/guide.md#setup"
private let fileLink = "file:///Users/me/docs/guide.md#setup"

private typealias Entry = PasteboardLinkRewriter.Entry

private func text(_ type: String, _ string: String) -> Entry {
    Entry(type: type, data: Data(string.utf8))
}

private func plist(_ type: String, _ value: Any, format: PropertyListSerialization.PropertyListFormat) throws -> Entry {
    Entry(type: type, data: try PropertyListSerialization.data(fromPropertyList: value, format: format, options: 0))
}

private func decoded(_ entry: Entry?) throws -> Any? {
    let data = try #require(entry?.data)
    return try PropertyListSerialization.propertyList(from: data, format: nil)
}

@Suite("PasteboardLinkRewriter: no mdv-doc URLs in drags")
struct PasteboardLinkRewriterTests {
    @Test("a pasteboard without mdv-doc URLs is left alone")
    func untouched() {
        let entries = [text("public.url", "https://example.com/"), text("public.utf8-plain-text", "hello")]
        #expect(PasteboardLinkRewriter.rewrite(entries, token: token) == nil)
    }

    @Test("a dragged link's URL and text become the file: URL; the title is kept")
    func link() throws {
        let entries = [
            text("public.url", documentLink),
            text("public.url-name", "Guide"),
            text("public.utf8-plain-text", documentLink),
        ]
        let rewritten = try #require(PasteboardLinkRewriter.rewrite(entries, token: token))
        #expect(
            rewritten == [
                text("public.url", fileLink), text("public.url-name", "Guide"),
                text("public.utf8-plain-text", fileLink),
            ])
    }

    @Test("the scheme matches in any case", arguments: ["MDV-DOC", "Mdv-Doc"])
    func schemeCase(scheme: String) throws {
        let link = documentLink.replacingOccurrences(of: "mdv-doc", with: scheme)
        let rewritten = try #require(PasteboardLinkRewriter.rewrite([text("public.url", link)], token: token))
        #expect(rewritten == [text("public.url", fileLink)])
    }

    @Test(
        "property lists of URLs and titles are rewritten in their own format",
        arguments: [PropertyListSerialization.PropertyListFormat.binary, .xml])
    func propertyLists(format: PropertyListSerialization.PropertyListFormat) throws {
        let entries = [
            try plist("WebURLsWithTitlesPboardType", [[documentLink], ["Guide"]], format: format),
            try plist("Apple URL pasteboard type", [documentLink, ""], format: format),
        ]
        let rewritten = try #require(PasteboardLinkRewriter.rewrite(entries, token: token))
        #expect(rewritten.map(\.type) == entries.map(\.type))
        #expect(try decoded(rewritten.first) as? [[String]] == [[fileLink], ["Guide"]])
        #expect(try decoded(rewritten.last) as? [String] == [fileLink, ""])
        var actualFormat = PropertyListSerialization.PropertyListFormat.openStep
        _ = try PropertyListSerialization.propertyList(
            from: try #require(rewritten.first?.data), format: &actualFormat)
        #expect(actualFormat == format)
    }

    @Test("entries that only mention an mdv-doc URL are dropped; the rest stay")
    func dropped() throws {
        let image = Entry(type: "public.tiff", data: Data([0x4D, 0x4D, 0x00, 0x2A]))
        let entries = [
            text("public.url", documentLink),
            text("public.html", "<a href=\"\(documentLink)\">Guide</a>"),
            Entry(type: "public.utf16-plain-text", data: try #require(documentLink.data(using: .utf16LittleEndian))),
            Entry(type: "binary", data: Data([0xFF, 0xFE]) + Data(documentLink.utf8)),
            try plist("nested", ["k": Data(documentLink.utf8)], format: .binary),
            image,
        ]
        let rewritten = try #require(PasteboardLinkRewriter.rewrite(entries, token: token))
        #expect(rewritten == [text("public.url", fileLink), image])
    }

    @Test("an mdv-doc URL for another window, or not a file, is dropped")
    func unresolvable() throws {
        let other = "mdv-doc://00000000-0000-0000-0000-000000000000/Users/me/docs/guide.md"
        let rewritten = try #require(
            PasteboardLinkRewriter.rewrite(
                [text("public.url", other), text("public.url-name", "Guide")], token: token))
        #expect(rewritten == [text("public.url-name", "Guide")])
    }
}
