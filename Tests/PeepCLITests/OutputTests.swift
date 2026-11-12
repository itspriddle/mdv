import Foundation
import MdvCore
import Testing

@Suite("Output flags")
struct OutputTests {
    @Test("--html prints one complete page with inline CSS, titled by the first heading")
    func htmlPage() async throws {
        let folder = try TempFolder()
        let input = try folder.fixture("hello.md")
        let result = await CLIHarness.run(["--html", input])
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("<!doctype html>"))
        #expect(result.stdout.hasSuffix("</html>\n"))
        #expect(result.stdout.contains("<title>Hello</title>"))
        #expect(result.stdout.contains("<style id=\"mdv-theme\">"))
        #expect(result.stdout.contains("<em>Markdown</em>"))
        #expect(result.stdout.components(separatedBy: "<!doctype html>").count == 2)
    }

    @Test("--html uses a bundled frontmatter theme for the page")
    func frontmatterTheme() async throws {
        let folder = try TempFolder()
        let result = await CLIHarness.run(["--html", try folder.fixture("serif-theme.md")])
        #expect(result.status == 0)
        #expect(result.stdout.contains(Theme.serif.layerCSS))
    }

    @Test("--fragment prints only the body HTML")
    func fragment() async throws {
        let result = await CLIHarness.run(["--fragment"], stdin: "# Title\n\nText.\n")
        #expect(result.status == 0)
        #expect(!result.stdout.contains("<html"))
        #expect(!result.stdout.contains("<style"))
        #expect(!result.stdout.contains("<article"))
        #expect(result.stdout.hasPrefix("<h1 id=\"title\">"))
        #expect(result.stdout.hasSuffix("<p>Text.</p>\n"))
    }

    @Test("--fragment with several inputs prints them in order, standard input where '-' is")
    func severalFragments() async throws {
        let folder = try TempFolder()
        let first = try folder.fixture("hello.md")
        let second = try folder.fixture("second.md")
        let result = await CLIHarness.run(["--fragment", second, "-", first], stdin: "Piped\n")
        #expect(result.status == 0)
        let secondIndex = try #require(result.stdout.range(of: "Second")).lowerBound
        let pipedIndex = try #require(result.stdout.range(of: "Piped")).lowerBound
        let helloIndex = try #require(result.stdout.range(of: "Hello")).lowerBound
        #expect(secondIndex < pipedIndex && pipedIndex < helloIndex)
    }

    @Test("several pages to standard output is a usage error", arguments: [["--html"], ["-o", "out.html"]])
    func severalPages(flags: [String]) async throws {
        let folder = try TempFolder()
        let result = await CLIHarness.run(flags + [try folder.fixture("hello.md"), try folder.fixture("second.md")])
        #expect(result.status == 64)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("run mdv once per file"))
        #expect(!FileManager.default.fileExists(atPath: "out.html"))
    }

    @Test("--fragment with --output still takes one input")
    func fragmentOutputSeveral() async throws {
        let folder = try TempFolder()
        let result = await CLIHarness.run([
            "--fragment", "-o", folder.path("out.html"), try folder.fixture("hello.md"),
            try folder.fixture("second.md"),
        ])
        #expect(result.status == 64)
        #expect(!FileManager.default.fileExists(atPath: folder.path("out.html")))
    }

    @Test("--output writes what standard output would get, and nothing to standard output")
    func outputFile() async throws {
        let folder = try TempFolder()
        let input = try folder.fixture("hello.md")
        let printed = await CLIHarness.run(["--html", input])
        let written = await CLIHarness.run(["--output", folder.path("hello.html"), input])
        #expect(written.status == 0)
        #expect(written.stdout.isEmpty)
        #expect(written.stderr.isEmpty)
        #expect(try folder.contents("hello.html") == printed.stdout)

        let fragment = await CLIHarness.run(["--fragment", "-o", folder.path("body.html"), input])
        #expect(fragment.status == 0)
        #expect(try folder.contents("body.html").hasPrefix("<h1"))
    }

    @Test("-o - is standard output")
    func outputDash() async throws {
        let result = await CLIHarness.run(["-o", "-"], stdin: "# Dash\n")
        #expect(result.status == 0)
        #expect(result.stdout.contains("<title>Dash</title>"))
    }

    @Test("--output replaces an existing file atomically (a new file renamed over it)")
    func outputReplacesAtomically() async throws {
        let folder = try TempFolder()
        let target = try folder.file("out.html", "old")
        let before = try FileManager.default.attributesOfItem(atPath: target)[.systemFileNumber] as? Int
        let result = await CLIHarness.run(["-o", target], stdin: "# New\n")
        #expect(result.status == 0)
        let after = try FileManager.default.attributesOfItem(atPath: target)[.systemFileNumber] as? Int
        #expect(before != after)
        #expect(try folder.contents("out.html").contains("<title>New</title>"))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.url.path)
        #expect(leftovers == ["out.html"])
    }

    @Test("--output leaves an existing file alone when an input fails")
    func outputUntouchedOnInputError() async throws {
        let folder = try TempFolder()
        let target = try folder.file("out.html", "old")
        let result = await CLIHarness.run(["-o", target, folder.path("missing.md")])
        #expect(result.status == 66)
        #expect(try folder.contents("out.html") == "old")
    }

    @Test("--output refuses to overwrite its input, by path, symbolic link, or hard link")
    func outputNeverOverwritesInput() async throws {
        let folder = try TempFolder()
        let input = try folder.file("doc.md", "# Keep me\n")
        try FileManager.default.createSymbolicLink(atPath: folder.path("link.md"), withDestinationPath: input)
        try FileManager.default.linkItem(atPath: input, toPath: folder.path("hard.md"))
        for target in [input, folder.path("link.md"), folder.path("hard.md"), folder.url.path + "/./doc.md"] {
            let result = await CLIHarness.run(["-o", target, input])
            #expect(result.status == 64, "\(target)")
            #expect(result.stderr == "mdv: \(target): refusing to overwrite an input file\n")
            #expect(try folder.contents("doc.md") == "# Keep me\n")
        }
    }

    @Test("--output into a missing folder exits 73 and creates nothing")
    func outputCannotCreate() async throws {
        let folder = try TempFolder()
        let target = folder.path("missing/out.html")
        let result = await CLIHarness.run(["-o", target], stdin: "# x\n")
        #expect(result.status == 73)
        #expect(result.stderr.hasPrefix("mdv: \(target): "))
        #expect(result.stderr.split(separator: "\n").count == 1)
        #expect(!FileManager.default.fileExists(atPath: folder.path("missing")))
    }

    @Test("an empty --output is a usage error")
    func emptyOutputName() async {
        let result = await CLIHarness.run(["-o", ""], stdin: "x")
        #expect(result.status == 64)
    }

    @Test("a failing standard output exits 74")
    func standardOutputFailure() async throws {
        struct Broken: Error {}
        let result = await CLIHarness.run(["--html"], stdin: Data("x".utf8), failingOutput: Broken())
        #expect(result.status == 74)
        #expect(result.stderr.hasPrefix("mdv: stdout: "))
    }
}
