import Foundation
import Testing

@testable import MdvCore

/// Minimal files whose leading bytes sniff as each format.
enum ImageBytes {
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D])
    static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10])
    static let gif = Data("GIF89a\u{1}\0\u{1}\0".utf8)
    static let webp = Data("RIFF\u{1A}\0\0\0WEBPVP8L".utf8)
    static let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>"#.utf8)
}

/// A temporary folder tree, removed when the value is deinitialized.
final class TemporaryTree {
    let root: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "mdv-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Real path (`/private/var/...`), so expectations compare with what the policy returns.
        root = URL(filePath: try #require(LocalResourceRoot.realPath(base.path)), directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func path(_ relative: String) -> String {
        root.appending(path: relative).path(percentEncoded: false)
    }

    @discardableResult
    func write(_ relative: String, _ data: Data = Data()) throws -> String {
        let url = root.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url.path(percentEncoded: false)
    }

    func mkdir(_ relative: String) throws {
        try FileManager.default.createDirectory(at: root.appending(path: relative), withIntermediateDirectories: true)
    }

    func symlink(_ relative: String, to destination: String) throws {
        try FileManager.default.createSymbolicLink(atPath: path(relative), withDestinationPath: destination)
    }
}

@Suite("DocumentURLScheme")
struct DocumentURLSchemeTests {
    static let sharedToken = "0a1b2c3d-0000-4000-8000-000000000000"
    let token = sharedToken

    @Test("builds mdv-doc://token/<absolute path>, percent-encoding each segment")
    func builds() throws {
        let url = try #require(DocumentURLScheme.url(token: token, filePath: "/Users/me/My Docs/a#b?c%d.md"))
        #expect(url.absoluteString == "mdv-doc://\(token)/Users/me/My%20Docs/a%23b%3Fc%25d.md")
        #expect(DocumentURLScheme.filePath(from: url, token: token) == "/Users/me/My Docs/a#b?c%d.md")
    }

    @Test("round-trips non-ASCII names")
    func unicode() throws {
        let path = "/tmp/résumé/图片.png"
        let url = try #require(DocumentURLScheme.url(token: token, filePath: path))
        #expect(DocumentURLScheme.filePath(from: url, token: token) == path)
    }

    @Test("relative URLs resolve against the document like file: URLs")
    func relativeResolution() throws {
        let document = try #require(DocumentURLScheme.url(token: token, filePath: "/repo/docs/README.md"))
        let sibling = try #require(URL(string: "../images/x.png", relativeTo: document))
        #expect(DocumentURLScheme.filePath(from: sibling.absoluteURL, token: token) == "/repo/images/x.png")
        let nested = try #require(URL(string: "img/y.svg?v=2#frag", relativeTo: document))
        #expect(DocumentURLScheme.filePath(from: nested.absoluteURL, token: token) == "/repo/docs/img/y.svg")
    }

    @Test("refuses relative and unclean paths when building")
    func buildRefuses() throws {
        #expect(DocumentURLScheme.url(token: token, filePath: "relative.md") == nil)
        #expect(DocumentURLScheme.url(token: token, filePath: "/a/../b.md") == nil)
        #expect(DocumentURLScheme.url(token: token, filePath: "/a/./b.md") == nil)
        #expect(DocumentURLScheme.url(token: token, filePath: "/a//b.md") == nil)
        #expect(DocumentURLScheme.url(token: token, filePath: "/") == nil)
        #expect(
            DocumentURLScheme.url(token: token, fileURL: try #require(URL(string: "https://example.com/a.md"))) == nil)
    }

    @Test(
        "refuses other schemes, tokens, authority parts, and unclean segments",
        arguments: [
            "file:///repo/a.png",
            "https://\(DocumentURLSchemeTests.sharedToken)/repo/a.png",
            "mdv-doc://another-token/repo/a.png",
            "mdv-doc://user@\(DocumentURLSchemeTests.sharedToken)/repo/a.png",
            "mdv-doc://\(DocumentURLSchemeTests.sharedToken):80/repo/a.png",
            "mdv-doc://\(DocumentURLSchemeTests.sharedToken)/repo/%2e%2e/etc/a.png",
            "mdv-doc://\(DocumentURLSchemeTests.sharedToken)/repo/%2E%2E/etc/a.png",
            "mdv-doc://\(DocumentURLSchemeTests.sharedToken)/repo/.%2e/etc/a.png",
            "mdv-doc://\(DocumentURLSchemeTests.sharedToken)/repo/../etc/a.png",
            "mdv-doc://\(DocumentURLSchemeTests.sharedToken)/repo/./a.png",
            "mdv-doc://\(DocumentURLSchemeTests.sharedToken)/repo/%2e/a.png",
            "mdv-doc://\(DocumentURLSchemeTests.sharedToken)/repo/..%2fetc/a.png",
            "mdv-doc://\(DocumentURLSchemeTests.sharedToken)/repo%2f..%2f..%2fetc/a.png",
            "mdv-doc://\(DocumentURLSchemeTests.sharedToken)/repo//a.png",
            "mdv-doc://\(DocumentURLSchemeTests.sharedToken)/repo/img/",
            "mdv-doc://\(DocumentURLSchemeTests.sharedToken)/repo/a%00.png",
            "mdv-doc://\(DocumentURLSchemeTests.sharedToken)",
        ])
    func refuses(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(DocumentURLScheme.filePath(from: url, token: Self.sharedToken) == nil)
    }

    @Test("tokens are random lowercase UUIDs")
    func tokens() {
        let token = DocumentURLScheme.makeToken()
        #expect(token == token.lowercased())
        #expect(UUID(uuidString: token) != nil)
        #expect(token != DocumentURLScheme.makeToken())
    }
}

@Suite("ImageFormat")
struct ImageFormatTests {
    @Test("maps extensions case-insensitively")
    func extensions() {
        #expect(ImageFormat(fileExtension: "PNG") == .png)
        #expect(ImageFormat(fileExtension: "jpg") == .jpeg)
        #expect(ImageFormat(fileExtension: "JPEG") == .jpeg)
        #expect(ImageFormat(fileExtension: "gif") == .gif)
        #expect(ImageFormat(fileExtension: "webp") == .webp)
        #expect(ImageFormat(fileExtension: "svg") == .svg)
        for other in ["", "md", "txt", "html", "svgz", "pdf", "png.txt", "heic"] {
            #expect(ImageFormat(fileExtension: other) == nil, "\(other)")
        }
    }

    @Test("sniffs each format")
    func sniffs() {
        #expect(ImageFormat.sniff(ImageBytes.png) == .png)
        #expect(ImageFormat.sniff(ImageBytes.jpeg) == .jpeg)
        #expect(ImageFormat.sniff(ImageBytes.gif) == .gif)
        #expect(ImageFormat.sniff(ImageBytes.webp) == .webp)
        #expect(ImageFormat.sniff(ImageBytes.svg) == .svg)
    }

    @Test(
        "sniffs SVG after a BOM, XML declaration, comments, and doctype",
        arguments: [
            "\u{FEFF}<svg>",
            "  \n<?xml version=\"1.0\"?>\n<!-- made by hand -->\n<svg width=\"1\">",
            "<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" \"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">\n<svg/>",
        ])
    func svgProlog(_ text: String) {
        #expect(ImageFormat.sniff(Data(text.utf8)) == .svg)
    }

    @Test(
        "does not sniff text, HTML, or SVG-lookalikes as images",
        arguments: [
            "", "hello", "# Markdown", "<html><svg></svg></html>", "<svgx>", "<!-- never closed <svg>",
            "<!DOCTYPE svg [<!ENTITY x \"y\">]><svg>", "RIFF\0\0\0\0WAVE", "GIF90a",
        ])
    func notImages(_ text: String) {
        #expect(ImageFormat.sniff(Data(text.utf8)) == nil)
    }
}

@Suite("LocalResourceRoot")
struct LocalResourceRootTests {
    @Test("is the document's folder outside a git repository")
    func folder() throws {
        let tree = try TemporaryTree()
        let document = try tree.write("docs/README.md")
        let home = tree.root.appending(path: "home")
        #expect(LocalResourceRoot.forDocument(at: URL(filePath: document), homeDirectory: home) == tree.path("docs"))
    }

    @Test("widens to the enclosing git repository (.git directory or file)", arguments: [true, false])
    func repository(gitIsDirectory: Bool) throws {
        let tree = try TemporaryTree()
        if gitIsDirectory {
            try tree.mkdir("repo/.git")
        } else {
            try tree.write("repo/.git", Data("gitdir: ../elsewhere".utf8))
        }
        let document = try tree.write("repo/docs/guide/README.md")
        let home = tree.root.appending(path: "home")
        #expect(LocalResourceRoot.forDocument(at: URL(filePath: document), homeDirectory: home) == tree.path("repo"))
    }

    @Test("never widens to the home folder")
    func notHome() throws {
        let tree = try TemporaryTree()
        try tree.mkdir("home/.git")
        let document = try tree.write("home/notes/todo.md")
        let home = tree.root.appending(path: "home")
        #expect(
            LocalResourceRoot.forDocument(at: URL(filePath: document), homeDirectory: home) == tree.path("home/notes"))
    }

    @Test("resolves a symlinked document folder to its real path")
    func symlinkedFolder() throws {
        let tree = try TemporaryTree()
        let document = try tree.write("real/README.md")
        try tree.symlink("alias", to: tree.path("real"))
        let viaAlias = URL(filePath: tree.path("alias/README.md"))
        #expect(LocalResourceRoot.forDocument(at: viaAlias, homeDirectory: tree.root) == tree.path("real"))
        #expect(
            LocalResourceRoot.forDocument(at: URL(filePath: document), homeDirectory: tree.root) == tree.path("real"))
    }

    @Test("is nil when the folder doesn't exist")
    func missing() {
        #expect(LocalResourceRoot.forDocument(at: URL(filePath: "/nonexistent-\(UUID().uuidString)/a.md")) == nil)
    }
}

@Suite("ContentSecurityPolicy")
struct ContentSecurityPolicyTests {
    @Test("standalone HTML keeps file: and data: images")
    func standalone() {
        #expect(
            ContentSecurityPolicy.standalone.header
                == "default-src 'none'; style-src 'unsafe-inline'; img-src file: data:;")
        #expect(HTMLDocument(title: "t", body: "").html.contains(ContentSecurityPolicy.standalone.header))
    }

    @Test("the viewer allows only the document scheme and data: images")
    func viewer() {
        #expect(
            ContentSecurityPolicy.viewer.header
                == "default-src 'none'; style-src 'unsafe-inline'; img-src mdv-doc: data:;")
        let html = HTMLDocument(title: "t", body: "", contentSecurityPolicy: .viewer).html
        #expect(html.contains(ContentSecurityPolicy.viewer.header))
        #expect(!html.contains("file:"))
    }
}
