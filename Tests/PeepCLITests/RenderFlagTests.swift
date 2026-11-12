import Foundation
import MdvCore
import Testing

/// The Rendering flags, wiki links, root-relative links, and frontmatter diagnostics (#65).
@Suite("Render flags")
struct RenderFlagTests {
    // MARK: Frontmatter

    @Test("--frontmatter table shows the frontmatter; hidden (the default) strips it")
    func frontmatter() async {
        let source = "---\ntitle: Notes\nauthor: Ada\n---\n# Body\n"
        let table = await CLIHarness.run(["--fragment", "--frontmatter", "table"], stdin: source)
        let hidden = await CLIHarness.run(["--fragment"], stdin: source)
        let explicit = await CLIHarness.run(["--fragment", "--frontmatter", "hidden"], stdin: source)
        #expect(table.status == 0)
        #expect(table.stdout.contains("<table"))
        #expect(table.stdout.contains("Ada"))
        #expect(!hidden.stdout.contains("Ada"))
        #expect(explicit.stdout == hidden.stdout)
    }

    @Test("an unknown --frontmatter mode is a usage error")
    func unknownFrontmatter() async {
        let result = await CLIHarness.run(["--html", "--frontmatter", "yaml"], stdin: "x")
        #expect(result.status == 64)
        #expect(result.stdout.isEmpty)
    }

    // MARK: Source lines, highlighting, anchors, remote images

    @Test("--source-lines adds data-source-line; off by default")
    func sourceLines() async {
        let enabled = await CLIHarness.run(["--fragment", "--source-lines"], stdin: "# A\n\ntext\n")
        let off = await CLIHarness.run(["--fragment"], stdin: "# A\n\ntext\n")
        #expect(enabled.stdout.contains("data-source-line=\"3\""))
        #expect(!off.stdout.contains("data-source-line"))
    }

    @Test("--no-highlight leaves fenced code plain")
    func highlighting() async {
        let source = "```swift\nlet x = 1\n```\n"
        let enabled = await CLIHarness.run(["--fragment"], stdin: source)
        let off = await CLIHarness.run(["--fragment", "--no-highlight"], stdin: source)
        #expect(enabled.stdout.contains("hljs-"))
        #expect(!off.stdout.contains("hljs-"))
        #expect(off.stdout.contains("let x = 1"))
    }

    @Test("--no-heading-anchors drops heading ids")
    func headingAnchors() async {
        let enabled = await CLIHarness.run(["--fragment"], stdin: "# Hello\n")
        let off = await CLIHarness.run(["--fragment", "--no-heading-anchors"], stdin: "# Hello\n")
        #expect(enabled.stdout.contains("id=\"hello\""))
        #expect(!off.stdout.contains("id=\"hello\""))
        #expect(off.stdout.contains("Hello</h1>"))
    }

    @Test("--block-remote-images replaces remote images; they're kept by default")
    func remoteImages() async {
        let source = "![Build](https://img.example/badge.svg)\n"
        let kept = await CLIHarness.run(["--fragment"], stdin: source)
        let blocked = await CLIHarness.run(["--fragment", "--block-remote-images"], stdin: source)
        #expect(kept.stdout.contains("<img src=\"https://img.example/badge.svg\""))
        #expect(blocked.stdout.contains("class=\"remote-image\""))
        #expect(!blocked.stdout.contains("<img"))
    }

    @Test("there is no --no-sanitize: raw scripts are always removed")
    func noSanitizeFlag() async {
        let refused = await CLIHarness.run(["--html", "--no-sanitize"], stdin: "x")
        #expect(refused.status == 64)
        let result = await CLIHarness.run(["--fragment"], stdin: "<script>alert(1)</script>\n")
        #expect(!result.stdout.contains("<script"))
    }

    @Test(
        "Rendering flags without HTML output are a usage error",
        arguments: [
            ["--source-lines"], ["--wiki-links"], ["--no-wiki-links"], ["--verbose"], ["--frontmatter", "table"],
            ["--no-highlight"], ["--block-remote-images"], ["--no-heading-anchors"],
        ])
    func needHTMLOutput(flags: [String]) async throws {
        let folder = try TempFolder()
        let path = try folder.file("a.md", "# A\n")
        let result = await CLIHarness.run(flags + [path])
        #expect(result.status == 64)
        #expect(result.openedInApp.isEmpty)
        #expect(result.stderr.contains("add --html, --fragment, or --output"))
    }

    // MARK: Wiki links

    /// `repo/` (a git work tree) with `docs/index.md` linking to pages in its own folder,
    /// elsewhere in the repository, outside it, and through symbolic links out of it.
    private static func wikiTree() throws -> (folder: TempFolder, document: String) {
        let folder = try TempFolder()
        let manager = FileManager.default
        for path in ["repo/.git", "repo/docs", "repo/guides", "outside"] {
            try manager.createDirectory(at: folder.url.appending(path: path), withIntermediateDirectories: true)
        }
        try folder.file("repo/docs/Local Page.md", "# Local\n")
        try folder.file("repo/guides/Setup.md", "# Setup\n")
        try folder.file("outside/Secret.md", "# Secret\n")
        try manager.createSymbolicLink(
            atPath: folder.path("repo/docs/Linked.md"), withDestinationPath: folder.path("outside/Secret.md"))
        try manager.createSymbolicLink(
            atPath: folder.path("repo/docs/escape"), withDestinationPath: folder.path("outside"))
        let document = try folder.file(
            "repo/docs/index.md",
            "[[Local Page]] [[Setup]] [[Secret]] [[Linked]] [[escape/Secret]] [[#Top]]\n\n# Top\n")
        return (folder, document)
    }

    @Test("--wiki-links resolves pages from the document's folder, then its allowed root")
    func wikiLinksResolve() async throws {
        let (folder, document) = try Self.wikiTree()
        let result = await CLIHarness.run(["--fragment", "--wiki-links", document])
        #expect(result.status == 0)
        #expect(result.stdout.contains("<a class=\"wikilink\" href=\"Local%20Page.md\">"))
        #expect(result.stdout.contains("<a class=\"wikilink\" href=\"../guides/Setup.md\">"))
        #expect(result.stdout.contains("<a class=\"wikilink\" href=\"#top\">"))
        _ = folder
    }

    @Test("wiki links never resolve outside the root or through a symbolic link")
    func wikiLinksStayInRoot() async throws {
        let (folder, document) = try Self.wikiTree()
        let result = await CLIHarness.run(["--fragment", "--wiki-links", document])
        #expect(result.status == 0)
        #expect(!result.stdout.contains("Secret.md"))
        #expect(!result.stdout.contains("Linked.md"))
        #expect(!result.stdout.contains("href=\"escape"))
        // Secret, Linked, and escape/Secret are all missing.
        #expect(result.stdout.components(separatedBy: "wikilink-missing").count - 1 == 3)
        _ = folder
    }

    @Test("standard input has no resolver: page links are missing, [[#Heading]] works")
    func wikiLinksStandardInput() async {
        let result = await CLIHarness.run(["--fragment", "--wiki-links"], stdin: "[[Page]] [[#Top]]\n\n# Top\n")
        #expect(result.status == 0)
        #expect(result.stdout.contains("<a class=\"wikilink wikilink-missing\">"))
        #expect(result.stdout.contains("<a class=\"wikilink\" href=\"#top\">"))
    }

    @Test("wiki links are off by default, and the document's mdv.wikilinks turns them on")
    func wikiLinksDefault() async {
        let plain = await CLIHarness.run(["--fragment"], stdin: "[[#Top]]\n\n# Top\n")
        let document = await CLIHarness.run(
            ["--fragment"], stdin: "---\nmdv: { wikilinks: true }\n---\n[[#Top]]\n\n# Top\n")
        #expect(!plain.stdout.contains("wikilink"))
        #expect(document.stdout.contains("class=\"wikilink\""))
    }

    @Test(
        "--wiki-links/--no-wiki-links beat the document's mdv.wikilinks",
        arguments: [("false", "--wiki-links", true), ("true", "--no-wiki-links", false)])
    func wikiLinksFlagBeatsDocument(document: String, flag: String, links: Bool) async {
        let source = "---\nmdv: { wikilinks: \(document) }\n---\n[[#Top]]\n\n# Top\n"
        let result = await CLIHarness.run(["--fragment", flag], stdin: source)
        #expect(result.status == 0)
        #expect(result.stdout.contains("class=\"wikilink\"") == links)
    }

    // MARK: Root-relative links

    @Test("root-relative URLs resolve against a file's allowed root; stdin keeps them as written")
    func rootRelative() async throws {
        let folder = try TempFolder()
        try FileManager.default.createDirectory(
            at: folder.url.appending(path: "repo/.git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: folder.url.appending(path: "repo/docs"), withIntermediateDirectories: true)
        let source = "![x](/img/x.png) [g](/docs/guide.md)\n"
        let document = try folder.file("repo/docs/a.md", source)
        let file = await CLIHarness.run(["--fragment", document])
        // A real path: the temp folder is under /var, a link to /private/var.
        let root = try #require(LocalResourceRoot.forDocument(at: URL(fileURLWithPath: document)))
        #expect(root.hasSuffix("/repo"))
        #expect(file.stdout.contains("src=\"\(root)/img/x.png\""))
        #expect(file.stdout.contains("href=\"\(root)/docs/guide.md\""))
        let stdin = await CLIHarness.run(["--fragment"], stdin: source)
        #expect(stdin.stdout.contains("src=\"/img/x.png\""))
    }

    // MARK: Diagnostics

    @Test("ignored frontmatter keys are warnings on standard error, never standard output")
    func ignoredKeys() async {
        let source = "---\nmdv:\n  sanitize: false\n  flavor: markdown\n---\n# Hi\n"
        let result = await CLIHarness.run(["--fragment"], stdin: source)
        #expect(result.status == 0)
        #expect(
            result.stderr.contains(
                "mdv: stdin: warning: mdv.sanitize isn't a setting a document can change "
                    + "(only flavor, theme, wikilinks); ignored.\n"
            ))
        #expect(result.stderr.contains("mdv: stdin: warning: mdv.flavor \"markdown\" isn't a flavor"))
        #expect(!result.stdout.contains("ignored"))
        #expect(result.stdout.contains("Hi</h1>"))
    }

    @Test("a document without ignored keys prints nothing on standard error")
    func quietByDefault() async {
        let result = await CLIHarness.run(["--fragment"], stdin: "---\nmdv: { flavor: gfm }\n---\n# Hi\n")
        #expect(result.stderr.isEmpty)
    }

    @Test("diagnostics name the input file")
    func diagnosticsNameFile() async throws {
        let folder = try TempFolder()
        let path = try folder.file("notes.md", "---\nmdv: { colour: red }\n---\nx\n")
        let result = await CLIHarness.run(["--fragment", path])
        #expect(result.stderr.hasPrefix("mdv: \(path): warning: mdv.colour isn't a setting"))
    }

    @Test("control characters in a document's keys are escaped before they reach the terminal")
    func controlCharacters() async {
        let source = "---\nmdv:\n  \"\\e[31mred\": 1\n---\nx\n"
        let result = await CLIHarness.run(["--fragment"], stdin: source)
        #expect(!result.stderr.unicodeScalars.contains("\u{1B}"))
        #expect(result.stderr.contains("mdv.\\u{1B}[31mred"))
    }

    @Test("--verbose reports the flavor and wiki links used and where they came from")
    func verbose() async {
        let plain = await CLIHarness.run(["--fragment", "--verbose"], stdin: "x\n")
        #expect(plain.stderr == "mdv: stdin: flavor gfm (default)\nmdv: stdin: wiki links off (default)\n")

        let document = "---\nmdv: { flavor: commonmark, wikilinks: true }\n---\nx\n"
        let fromDocument = await CLIHarness.run(["--fragment", "--verbose"], stdin: document)
        #expect(fromDocument.stderr.contains("flavor commonmark (the document's mdv.flavor)"))
        #expect(fromDocument.stderr.contains("wiki links on (the document's mdv.wikilinks)"))

        let pinned = await CLIHarness.run(
            ["--fragment", "--verbose", "--flavor", "gfm", "--no-wiki-links"], stdin: document)
        #expect(pinned.stderr.contains("flavor gfm (--flavor; the document's mdv.flavor commonmark wasn't used)"))
        #expect(pinned.stderr.contains("wiki links off (--no-wiki-links; the document's mdv.wikilinks wasn't used)"))
        #expect(!pinned.stdout.contains("flavor"))
    }

    @Test("the built binary keeps diagnostics on standard error")
    func endToEnd() throws {
        let folder = try TempFolder()
        let path = try folder.file("a.md", "---\nmdv: { sanitize: false }\n---\n# A\n")
        guard let result = try CLIBinary.run(["--fragment", "--verbose", path]) else {
            return
        }
        #expect(result.status == 0)
        #expect(result.stdout.hasPrefix("<h1"))
        #expect(!result.stdout.contains("mdv:"))
        #expect(result.stderr.contains("flavor gfm (default)"))
        #expect(result.stderr.contains("warning: mdv.sanitize"))
    }
}
