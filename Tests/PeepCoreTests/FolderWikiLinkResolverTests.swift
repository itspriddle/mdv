import Synchronization
import Testing

@testable import MdvCore

/// An in-memory folder tree: absolute folder path to its entries (folders end in `/`).
final class FakeFolderReader: WikiLinkFolderReader {
    private let tree: [String: [String]]
    private let reads = Mutex<[String]>([])

    init(_ tree: [String: [String]]) {
        self.tree = tree
    }

    var readPaths: [String] { reads.withLock { $0 } }

    func entries(ofFolderAtPath path: String) -> [WikiLinkFolderEntry]? {
        reads.withLock { $0.append(path) }
        return tree[path]?.map { name in
            name.hasSuffix("/")
                ? WikiLinkFolderEntry(name: String(name.dropLast()), isFolder: true)
                : WikiLinkFolderEntry(name: name, isFolder: false)
        }
    }
}

@Suite("Wiki links: folder resolution")
struct FolderWikiLinkResolverTests {
    /// /repo (the allowed root) with the document in /repo/docs/guide.
    static let tree: [String: [String]] = [
        "/repo": ["README.md", "Home.md", "docs/", ".git/", "Shared.md", "zeta/", "notes.txt"],
        "/repo/.git": ["Secret.md"],
        "/repo/docs": ["Home.md", "guide/", "Deep.md", "other/"],
        "/repo/docs/guide": ["index.md", "Page Name.md", "Setup/", ".Hidden.md", "image.png"],
        "/repo/docs/guide/Setup": ["Install.md"],
        "/repo/docs/other": ["Shared.md", "Install.md", "setup/"],
        "/repo/docs/other/setup": ["Install.md"],
        "/repo/zeta": ["Far.markdown", "Home.md"],
    ]

    static func resolver(
        _ tree: [String: [String]] = tree, root: String? = "/repo", entryLimit: Int = 10_000
    ) -> (FolderWikiLinkResolver, FakeFolderReader) {
        let reader = FakeFolderReader(tree)
        return (
            FolderWikiLinkResolver(
                documentFolder: "/repo/docs/guide", root: root, reader: reader, entryLimit: entryLimit),
            reader
        )
    }

    static func resolve(_ name: String, using resolver: FolderWikiLinkResolver) -> String? {
        WikiPage(name).flatMap(resolver.destination(for:))
    }

    @Test("the document's folder first, then the root breadth first, relative to the document")
    func order() {
        let (resolver, _) = Self.resolver()
        #expect(Self.resolve("Page Name", using: resolver) == "Page Name.md")
        #expect(Self.resolve("page-name", using: resolver) == "Page Name.md")
        // Root level beats /repo/docs/Home.md: breadth first from the root.
        #expect(Self.resolve("Home", using: resolver) == "../../Home.md")
        #expect(Self.resolve("Deep", using: resolver) == "../Deep.md")
        #expect(Self.resolve("Shared", using: resolver) == "../../Shared.md")
        #expect(Self.resolve("Far", using: resolver) == "../../zeta/Far.markdown")
        #expect(Self.resolve("Far.markdown", using: resolver) == "../../zeta/Far.markdown")
        #expect(Self.resolve("index.md", using: resolver) == "index.md")
    }

    @Test("folders in the name: under the document's folder first, then any folder path ending with them")
    func folders() {
        let (resolver, _) = Self.resolver()
        #expect(Self.resolve("setup/install", using: resolver) == "Setup/Install.md")
        #expect(Self.resolve("other/Install", using: resolver) == "../other/Install.md")
        #expect(Self.resolve("other/setup/Install", using: resolver) == "../other/setup/Install.md")
        #expect(Self.resolve("docs/Home", using: resolver) == "../Home.md")
        #expect(Self.resolve("zeta/Home", using: resolver) == "../../zeta/Home.md")
        #expect(Self.resolve("nowhere/Home", using: resolver) == nil)
    }

    @Test("never outside the root, never hidden entries, never non-Markdown files")
    func scope() {
        let (resolver, _) = Self.resolver()
        #expect(Self.resolve("Secret", using: resolver) == nil)
        #expect(Self.resolve(".git/Secret", using: resolver) == nil)
        #expect(Self.resolve(".Hidden", using: resolver) == nil)
        #expect(Self.resolve("notes", using: resolver) == nil)
        #expect(Self.resolve("image", using: resolver) == nil)
        #expect(Self.resolve("Nope", using: resolver) == nil)

        let outside = FakeFolderReader(["/elsewhere": ["Home.md"], "/repo/docs/guide": []])
        let confined = FolderWikiLinkResolver(documentFolder: "/repo/docs/guide", root: "/elsewhere", reader: outside)
        #expect(Self.resolve("Home", using: confined) == nil)
        #expect(!outside.readPaths.contains("/elsewhere"))
    }

    @Test("without a root, only the document's folder tree is searched")
    func noRoot() {
        let (resolver, reader) = Self.resolver(root: nil)
        #expect(Self.resolve("Install", using: resolver) == "Setup/Install.md")
        #expect(Self.resolve("Shared", using: resolver) == nil)
        #expect(reader.readPaths.allSatisfy { $0.hasPrefix("/repo/docs/guide") })
    }

    @Test("name order within a folder, whatever order the reader lists")
    func deterministic() {
        let (resolver, _) = Self.resolver([
            "/repo": ["docs/"], "/repo/docs": ["guide/"],
            "/repo/docs/guide": ["page-name.md", "Page Name.md", "PAGE-NAME.md"],
        ])
        #expect(Self.resolve("Page Name", using: resolver) == "Page Name.md")
    }

    @Test("the root is listed once per resolver, only when needed, and results are cached")
    func cached() {
        let (resolver, reader) = Self.resolver()
        #expect(Self.resolve("Page Name", using: resolver) != nil)
        #expect(reader.readPaths == ["/repo/docs/guide"])
        _ = Self.resolve("Home", using: resolver)
        _ = Self.resolve("Shared", using: resolver)
        _ = Self.resolve("Home", using: resolver)
        #expect(reader.readPaths.filter { $0 == "/repo" }.count == 1)
        #expect(Set(reader.readPaths).count == reader.readPaths.count)
    }

    @Test("the entry limit bounds the root search; pages past it are missing")
    func entryLimit() {
        var tree: [String: [String]] = ["/repo/docs/guide": []]
        tree["/repo"] = (0..<50).map { "f\($0)/" } + ["docs/"]
        for index in 0..<50 {
            tree["/repo/f\(index)"] = (0..<100).map { "n\($0).md" }
        }
        tree["/repo/f49"]?.append("Target.md")
        let (limited, reader) = Self.resolver(tree, entryLimit: 1_000)
        #expect(Self.resolve("Target", using: limited) == nil)
        #expect(reader.readPaths.count < 20)
        let (unlimited, _) = Self.resolver(tree, entryLimit: 10_000)
        #expect(Self.resolve("Target", using: unlimited) == "../../f49/Target.md")
    }

    @Test("an unreadable folder counts as empty")
    func unreadable() {
        let (resolver, _) = Self.resolver(["/repo": ["Home.md", "locked/"]])
        #expect(Self.resolve("Home", using: resolver) == "../../Home.md")
        #expect(Self.resolve("locked/x", using: resolver) == nil)
    }

    @Test("renders through HTMLRenderer as relative, encoded links")
    func rendering() {
        let (resolver, _) = Self.resolver()
        var options = RenderOptions()
        options.builtInPreprocessors = [.wikiLinks]
        let html = HTMLRenderer(options: options, wikiLinkResolver: resolver)
            .render("[[Page Name#Step One]] [[Home]] [[Nope]]").html
        #expect(
            html == "<p><a class=\"wikilink\" href=\"Page%20Name.md#step-one\">Page Name#Step One</a> "
                + "<a class=\"wikilink\" href=\"../../Home.md\">Home</a> "
                + "<a class=\"wikilink wikilink-missing\">Nope</a></p>\n"
        )
    }
}
