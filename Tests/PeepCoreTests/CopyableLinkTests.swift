import Foundation
import Testing

@testable import MdvCore

private let token = "0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0"

/// The page URL of `/Users/me/docs/README.md` in the window `token`, as the app loads it.
private let page = URL(string: "mdv-doc://\(token)/Users/me/docs/README.md")

/// Resolves `href` against the page, as WebKit does, then picks what Copy Link copies.
private func copied(_ href: String) throws -> String? {
    let base = try #require(page)
    let url = try href.isEmpty ? base : #require(URL(string: href, relativeTo: base)?.absoluteURL)
    return CopyableLink.url(for: url, token: token)?.absoluteString
}

@Suite("CopyableLink: what Copy Link copies")
struct CopyableLinkTests {
    @Test(
        "relative links copy the file: URL they name, keeping the fragment",
        arguments: [
            ("guide.md", "file:///Users/me/docs/guide.md"),
            ("sub/Guide.md#setup", "file:///Users/me/docs/sub/Guide.md#setup"),
            ("../other/notes.md", "file:///Users/me/other/notes.md"),
            ("/tmp/x.md", "file:///tmp/x.md"),
            ("my%20file.md", "file:///Users/me/docs/my%20file.md"),
            // File URLs use the file system's decomposed form; the fragment is kept as written.
            ("caf%C3%A9.md#%C3%A9t%C3%A9", "file:///Users/me/docs/cafe%CC%81.md#%C3%A9t%C3%A9"),
            ("image.png?raw=1", "file:///Users/me/docs/image.png"),
            ("sub/", "file:///Users/me/docs/sub/"),
            ("#install", "file:///Users/me/docs/README.md#install"),
            ("#", "file:///Users/me/docs/README.md"),
            ("", "file:///Users/me/docs/README.md"),
        ])
    func relative(href: String, expected: String) throws {
        let actual = try copied(href)
        #expect(actual == expected)
    }

    @Test(
        "other schemes are copied as resolved",
        arguments: [
            "https://example.com/a?b=c#d",
            "http://example.com/",
            "mailto:me@example.com",
            "file:///tmp/x.md",
            "javascript:alert(1)",
        ])
    func external(href: String) throws {
        #expect(try copied(href) == href)
    }

    @Test(
        "an mdv-doc URL that names no file in this window copies nothing",
        arguments: [
            "mdv-doc://another-token/Users/me/docs/guide.md",
            "MDV-DOC://another-token/x.md",
            "mdv-doc://\(token)/a/%2E%2E/b.md",
            "mdv-doc://\(token)/a/%2Fb.md",
            "mdv-doc://\(token)",
            "mdv-doc:relative",
            "mdv-doc://user@\(token)/x.md",
            "mdv-doc://\(token):80/x.md",
        ])
    func refused(href: String) throws {
        let url = try #require(URL(string: href))
        #expect(CopyableLink.url(for: url, token: token) == nil)
    }

    @Test("never copies an mdv-doc URL", arguments: ["guide.md", "#x", "", "sub/", "a%23b.md#c%20d", "//\(token)/y"])
    func neverInternal(href: String) throws {
        let result = try copied(href)
        #expect(result?.lowercased().hasPrefix("mdv-doc:") != true)
    }

    @Test("a URL without a scheme copies nothing")
    func schemeless() throws {
        let url = try #require(URL(string: "guide.md"))
        #expect(CopyableLink.url(for: url, token: token) == nil)
    }
}
