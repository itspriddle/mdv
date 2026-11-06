import Foundation
import Testing

@testable import MdvCore

@Suite("LocalImagePolicy")
struct LocalImagePolicyTests {
    let token = DocumentURLScheme.makeToken()
    let tree: TemporaryTree
    let policy: LocalImagePolicy

    /// `root/` is the allowed root; `outside/` is a sibling it must not reach.
    init() throws {
        tree = try TemporaryTree()
        try tree.mkdir("root")
        try tree.mkdir("outside")
        policy = try #require(LocalImagePolicy(token: token, root: tree.path("root")))
    }

    func url(_ relative: String) throws -> URL {
        try #require(DocumentURLScheme.url(token: token, filePath: tree.path(relative)))
    }

    func image(_ relative: String) throws -> LocalImage? {
        policy.image(for: try url(relative))
    }

    @Test("serves each image format from the root and from subfolders")
    func servesImages() throws {
        let files: [String: LocalImage] = [
            "root/a.png": LocalImage(data: ImageBytes.png, format: .png),
            "root/img/b.jpg": LocalImage(data: ImageBytes.jpeg, format: .jpeg),
            "root/img/deep/c.JPEG": LocalImage(data: ImageBytes.jpeg, format: .jpeg),
            "root/d.gif": LocalImage(data: ImageBytes.gif, format: .gif),
            "root/e.webp": LocalImage(data: ImageBytes.webp, format: .webp),
            "root/f.svg": LocalImage(data: ImageBytes.svg, format: .svg),
            "root/with space & ü.png": LocalImage(data: ImageBytes.png, format: .png),
        ]
        for (path, expected) in files {
            try tree.write(path, expected.data)
            #expect(try image(path) == expected, "\(path)")
        }
        #expect(try image("root/f.svg")?.mimeType == "image/svg+xml")
    }

    @Test("resolves a relative reference from the document like a browser would")
    func fromDocument() throws {
        try tree.write("root/images/x.png", ImageBytes.png)
        let documentPath = try tree.write("root/docs/README.md")
        let document = try #require(policy.documentURL(forFileAt: URL(filePath: documentPath)))
        #expect(document == (try url("root/docs/README.md")))
        let resolved = try #require(URL(string: "../images/x.png", relativeTo: document)).absoluteURL
        #expect(policy.image(for: resolved)?.format == .png)
    }

    @Test("refuses files outside the root, however the path is spelled")
    func outside() throws {
        try tree.write("outside/secret.png", ImageBytes.png)
        try tree.write("root/inside.png", ImageBytes.png)
        #expect(try image("outside/secret.png") == nil)
        // Lexical `..` and encoded forms never reach the file system.
        let base = "mdv-doc://\(token)\(tree.path("root"))"
        for spelling in ["/../outside/secret.png", "/%2e%2e/outside/secret.png", "/..%2foutside/secret.png"] {
            let crafted = try #require(URL(string: base + spelling))
            #expect(policy.image(for: crafted) == nil, "\(spelling)")
        }
        // WebKit-style resolution of `../` clamps nothing here: it names the outside file, which is refused.
        let document = try url("root/README.md")
        let resolved = try #require(URL(string: "../outside/secret.png", relativeTo: document)).absoluteURL
        #expect(policy.image(for: resolved) == nil)
        // An absolute path anywhere else is refused too.
        let absolute = try #require(DocumentURLScheme.url(token: token, filePath: "/System/Library/CoreServices/x.png"))
        #expect(policy.image(for: absolute) == nil)
    }

    @Test("refuses a sibling folder whose name starts with the root's")
    func prefixSibling() throws {
        try tree.write("root-other/a.png", ImageBytes.png)
        #expect(try image("root-other/a.png") == nil)
    }

    @Test("refuses symlinks that escape the root, and allows ones that stay inside")
    func symlinks() throws {
        try tree.write("outside/secret.png", ImageBytes.png)
        try tree.write("root/real/inside.png", ImageBytes.png)
        try tree.symlink("root/escape.png", to: tree.path("outside/secret.png"))
        try tree.symlink("root/relative-escape.png", to: "../outside/secret.png")
        try tree.symlink("root/escape-dir", to: tree.path("outside"))
        try tree.symlink("root/alias.png", to: "real/inside.png")
        try tree.symlink("root/alias-dir", to: "real")
        #expect(try image("root/escape.png") == nil)
        #expect(try image("root/relative-escape.png") == nil)
        #expect(try image("root/escape-dir/secret.png") == nil)
        #expect(try image("root/alias.png")?.format == .png)
        #expect(try image("root/alias-dir/inside.png")?.format == .png)
    }

    @Test("refuses an image-named symlink to a non-image file")
    func symlinkToText() throws {
        try tree.write("root/notes.txt", ImageBytes.png)
        try tree.symlink("root/notes.png", to: "notes.txt")
        #expect(try image("root/notes.png") == nil)
    }

    @Test("refuses non-image files under the root")
    func nonImages() throws {
        try tree.write("root/README.md", Data("# Hi".utf8))
        try tree.write("root/page.html", Data("<svg></svg>".utf8))
        try tree.write("root/.env", Data("SECRET=1".utf8))
        try tree.write("root/png", ImageBytes.png)
        for path in ["root/README.md", "root/page.html", "root/.env", "root/png"] {
            #expect(try image(path) == nil, "\(path)")
        }
    }

    @Test("refuses content that doesn't match its extension")
    func mismatchedContent() throws {
        try tree.write("root/text.png", Data("not a png".utf8))
        try tree.write("root/html.svg", Data("<html><script>x</script></html>".utf8))
        try tree.write("root/jpeg.png", ImageBytes.jpeg)
        try tree.write("root/svg.png", ImageBytes.svg)
        try tree.write("root/empty.gif")
        for path in ["root/text.png", "root/html.svg", "root/jpeg.png", "root/svg.png", "root/empty.gif"] {
            #expect(try image(path) == nil, "\(path)")
        }
    }

    @Test("refuses directories, missing files, FIFOs, and oversized files")
    func specialFiles() throws {
        try tree.mkdir("root/folder.png")
        #expect(try image("root/folder.png") == nil)
        #expect(try image("root/missing.png") == nil)
        #expect(mkfifo(tree.path("root/pipe.png"), 0o600) == 0)
        #expect(try image("root/pipe.png") == nil)  // Returns at once: no blocking open.

        try tree.write("root/big.png", ImageBytes.png + Data(count: 100))
        let small = try #require(LocalImagePolicy(token: token, root: tree.path("root"), maximumSize: 50))
        #expect(small.image(for: try url("root/big.png")) == nil)
        #expect(policy.image(for: try url("root/big.png")) != nil)
    }

    @Test("refuses other windows' tokens")
    func otherToken() throws {
        try tree.write("root/a.png", ImageBytes.png)
        let other = try #require(
            DocumentURLScheme.url(token: DocumentURLScheme.makeToken(), filePath: tree.path("root/a.png")))
        #expect(policy.image(for: other) == nil)
    }

    @Test("a symlinked root is resolved, so both spellings work and escapes still fail")
    func symlinkedRoot() throws {
        try tree.write("root/a.png", ImageBytes.png)
        try tree.symlink("root-link", to: tree.path("root"))
        let viaLink = try #require(LocalImagePolicy(token: token, root: tree.path("root-link")))
        #expect(viaLink.root == tree.path("root"))
        #expect(viaLink.image(for: try url("root-link/a.png"))?.format == .png)
        #expect(viaLink.image(for: try url("root/a.png"))?.format == .png)
    }

    @Test("is nil for a missing root")
    func missingRoot() {
        #expect(LocalImagePolicy(token: token, root: tree.path("nope")) == nil)
    }
}
