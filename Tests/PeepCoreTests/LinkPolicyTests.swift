import Foundation
import Testing

@testable import MdvCore

private let folder = URL(filePath: "/Users/me/docs/", directoryHint: .isDirectory)
private let document = URL(filePath: "/Users/me/docs/README.md")

/// Today's loader: `loadHTMLString` with the document's folder as the base URL.
private let context = LinkContext(pageURL: folder, documentFileURL: document)

/// Resolves `href` the way WebKit does against the page's base URL, then applies the policy.
private func action(_ href: String, in context: LinkContext = context) throws -> LinkAction {
    let base = try #require(context.pageURL)
    // `href=""` resolves to the base URL itself (`URL(string:)` rejects the empty string).
    let url = try href.isEmpty ? base : #require(URL(string: href, relativeTo: base)?.absoluteURL)
    return LinkPolicy.action(for: url, in: context)
}

@Suite("LinkPolicy: actions")
struct LinkPolicyTests {
    @Test(
        "in-page fragments scroll, raw (percent-encoded) and without navigating",
        arguments: [
            ("#install", "install"),
            ("#fn-1", "fn-1"),
            ("#fnref-1", "fnref-1"),
            ("#caf%C3%A9", "caf%C3%A9"),
            ("#a%20b", "a%20b"),
            ("#", ""),
            ("README.md#usage", "usage"),
            ("./README.md#usage", "usage"),
            ("/Users/me/docs/README.md#usage", "usage"),
            ("../docs/README.md#usage", "usage"),
        ])
    func fragments(href: String, fragment: String) throws {
        #expect(try action(href) == .scrollToFragment(fragment))
    }

    /// A link to a local Markdown file and the document it should open.
    struct MarkdownLink: Sendable, CustomTestStringConvertible {
        var href: String
        var path: String
        var fragment: String?
        var testDescription: String { href }
    }

    @Test(
        "local Markdown files open in mdv, keeping the fragment",
        arguments: [
            MarkdownLink(href: "guide.md", path: "/Users/me/docs/guide.md"),
            MarkdownLink(
                href: "sub/Guide.MARKDOWN#setup", path: "/Users/me/docs/sub/Guide.MARKDOWN", fragment: "setup"),
            MarkdownLink(href: "../other/notes.mdown", path: "/Users/me/other/notes.mdown"),
            MarkdownLink(href: "/tmp/x.mkd", path: "/tmp/x.mkd"),
            MarkdownLink(href: "file:///tmp/y.mkdn#a%20b", path: "/tmp/y.mkdn", fragment: "a%20b"),
            MarkdownLink(href: "my%20file.md", path: "/Users/me/docs/my file.md"),
        ])
    func markdown(link: MarkdownLink) throws {
        #expect(try action(link.href) == .openDocument(URL(filePath: link.path), fragment: link.fragment))
    }

    @Test(
        "other local files and folders are revealed in Finder, never opened",
        arguments: [
            ("image.png", "/Users/me/docs/image.png"),
            ("script.command", "/Users/me/docs/script.command"),
            ("/Applications/Calculator.app", "/Applications/Calculator.app"),
            ("notes.txt", "/Users/me/docs/notes.txt"),
            ("sub/", "/Users/me/docs/sub/"),
            ("README.md.zip", "/Users/me/docs/README.md.zip"),
        ])
    func otherFiles(href: String, path: String) throws {
        guard case .revealInFinder(let file) = try action(href) else {
            Issue.record("\(href) is not revealed")
            return
        }
        #expect(file.path(percentEncoded: false) == path)
    }

    @Test(
        "http, https, and mailto open in the default app",
        arguments: [
            "https://example.com/a?b=c#d", "http://example.com", "HTTPS://EXAMPLE.COM", "mailto:me@example.com",
        ])
    func external(href: String) throws {
        #expect(try action(href) == .openExternal(try #require(URL(string: href))))
    }

    @Test(
        "everything else is blocked",
        arguments: [
            "javascript:alert(1)", "JaVaScRiPt:alert(1)", "data:text/html,<b>x</b>", "vbscript:x",
            "ftp://example.com/x",
            "x-custom://open", "file://remotehost/etc/passwd.md", "about:blank", "tel:123", "ssh://host",
        ])
    func blocked(href: String) throws {
        guard let url = URL(string: href) else {
            return
        }
        #expect(LinkPolicy.action(for: url, in: context) == .blocked(url))
    }

    @Test("the blank href cmark's safe mode writes (and links to this document) are blocked")
    func blankLinks() throws {
        #expect(try action("") == .blocked(folder))
        #expect(try action("README.md") == .blocked(document))
    }

    @Test("a page loaded without a base URL keeps fragments in-page")
    func aboutBlank() throws {
        let blank = try #require(URL(string: "about:blank"))
        let context = LinkContext(pageURL: blank, documentFileURL: nil)
        #expect(
            LinkPolicy.action(for: try #require(URL(string: "about:blank#x")), in: context) == .scrollToFragment("x"))
    }

    /// The shape #18's scheme handler gives: the page is served as
    /// `mdv-doc://<window>/<path>`, and the loader maps such URLs back to files.
    @Test("a custom page scheme works through LinkContext alone")
    func schemeLoader() throws {
        let page = try #require(URL(string: "mdv-doc://w1/Users/me/docs/README.md"))
        let context = LinkContext(pageURL: page, documentFileURL: document) { url in
            guard url.scheme == "mdv-doc", url.host() == "w1" else {
                return nil
            }
            return URL(filePath: url.path(percentEncoded: false))
        }
        #expect(try action("#usage", in: context) == .scrollToFragment("usage"))
        #expect(try action("", in: context) == .blocked(page))
        #expect(
            try action("guide.md#x", in: context)
                == .openDocument(URL(filePath: "/Users/me/docs/guide.md"), fragment: "x"))
        #expect(try action("logo.png", in: context) == .revealInFinder(URL(filePath: "/Users/me/docs/logo.png")))
        #expect(
            try action("https://example.com", in: context)
                == .openExternal(try #require(URL(string: "https://example.com"))))
        // Plain file URLs are not local files for this loader.
        #expect(try action("file:///tmp/a.md", in: context) == .blocked(try #require(URL(string: "file:///tmp/a.md"))))
    }
}

@Suite("LinkPolicy: fragments and status")
struct LinkPolicyFragmentTests {
    @Test("fragment ids: raw first, then decoded, then each with user-content-")
    func candidates() {
        #expect(LinkPolicy.fragmentIDCandidates("foo") == ["foo", "user-content-foo"])
        #expect(
            LinkPolicy.fragmentIDCandidates("caf%C3%A9")
                == ["caf%C3%A9", "café", "user-content-caf%C3%A9", "user-content-café"])
        #expect(LinkPolicy.fragmentIDCandidates("") == [])
        // Not valid percent-encoding: only the raw form.
        #expect(LinkPolicy.fragmentIDCandidates("100%") == ["100%", "user-content-100%"])
    }

    @Test("# and #top mean the top of the page")
    func top() {
        #expect(LinkPolicy.fragmentMeansTop(""))
        #expect(LinkPolicy.fragmentMeansTop("TOP"))
        #expect(!LinkPolicy.fragmentMeansTop("topic"))
    }

    @Test("Markdown extensions match the declared document type")
    func extensions() {
        #expect(LinkPolicy.isMarkdownFile(URL(filePath: "/a/b.Md")))
        #expect(!LinkPolicy.isMarkdownFile(URL(filePath: "/a/b.md/", directoryHint: .isDirectory)))
        #expect(!LinkPolicy.isMarkdownFile(URL(filePath: "/a/md")))
    }

    @Test("status text says where a link goes")
    func status() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let file = URL(filePath: home).appending(path: "docs/guide.md")
        #expect(LinkPolicy.statusText(for: .scrollToFragment("caf%C3%A9")) == "#café")
        #expect(LinkPolicy.statusText(for: .openDocument(file, fragment: "a%20b")) == "~/docs/guide.md#a b")
        #expect(
            LinkPolicy.statusText(for: .revealInFinder(URL(filePath: "/tmp/x.png"))) == "Show in Finder: /tmp/x.png")
        let url = try #require(URL(string: "https://example.com/a"))
        #expect(LinkPolicy.statusText(for: .openExternal(url)) == "https://example.com/a")
        let blocked = try #require(URL(string: "javascript:alert(1)"))
        #expect(LinkPolicy.statusText(for: .blocked(blocked)) == "Blocked link: javascript:alert(1)")
    }
}
