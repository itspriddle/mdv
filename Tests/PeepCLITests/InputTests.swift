import Foundation
import Testing

@Suite("Inputs")
struct InputTests {
    @Test("no FILE reads standard input; the title falls back to 'stdin'")
    func standardInput() async {
        let result = await CLIHarness.run(["--html"], stdin: "Just a paragraph.\n")
        #expect(result.status == 0)
        #expect(result.stdout.contains("<title>stdin</title>"))
        #expect(result.stdout.contains("<p>Just a paragraph.</p>"))
    }

    @Test("a FILE without a heading is titled by its file name")
    func fileTitle() async throws {
        let folder = try TempFolder()
        let input = try folder.file("notes.md", "No heading here.\n")
        let result = await CLIHarness.run(["--html", input])
        #expect(result.stdout.contains("<title>notes.md</title>"))
    }

    @Test("a FILE is read instead of standard input")
    func fileBeatsStandardInput() async throws {
        let folder = try TempFolder()
        let result = await CLIHarness.run(["--fragment", try folder.fixture("hello.md")], stdin: "# Piped\n")
        #expect(result.stdout.contains("Hello"))
        #expect(!result.stdout.contains("Piped"))
    }

    @Test("empty input renders an empty page or fragment", arguments: ["file", "stdin"])
    func emptyInput(kind: String) async throws {
        let folder = try TempFolder()
        let arguments = kind == "file" ? [try folder.fixture("empty.md")] : []
        let page = await CLIHarness.run(["--html"] + arguments, stdin: "")
        #expect(page.status == 0)
        #expect(page.stderr.isEmpty)
        #expect(page.stdout.contains("<article class=\"markdown-body\">\n\n</article>"))
        let fragment = await CLIHarness.run(["--fragment"] + arguments, stdin: "")
        #expect(fragment.status == 0)
        #expect(fragment.stdout.isEmpty)
    }

    @Test("a missing FILE exits 66 with one line naming it")
    func missingFile() async throws {
        let folder = try TempFolder()
        let missing = folder.path("missing.md")
        let result = await CLIHarness.run(["--html", missing])
        #expect(result.status == 66)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr == "peep: \(missing): No such file or directory\n")
    }

    @Test("a folder exits 66")
    func folderInput() async throws {
        let folder = try TempFolder()
        let result = await CLIHarness.run(["--html", folder.url.path])
        #expect(result.status == 66)
        #expect(result.stderr == "peep: \(folder.url.path): Is a directory\n")
    }

    @Test("an unreadable FILE exits 66")
    func unreadableFile() async throws {
        let folder = try TempFolder()
        let input = try folder.file("secret.md", "# Secret\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: input)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: input) }
        let result = await CLIHarness.run(["--html", input])
        #expect(result.status == 66)
        #expect(result.stderr == "peep: \(input): Permission denied\n")
    }

    @Test("invalid UTF-8 exits 65, from a FILE or standard input")
    func invalidUTF8() async throws {
        let folder = try TempFolder()
        let input = try folder.fixture("invalid-utf8.md")
        let fromFile = await CLIHarness.run(["--html", input])
        #expect(fromFile.status == 65)
        #expect(fromFile.stdout.isEmpty)
        #expect(fromFile.stderr == "peep: \(input): not valid UTF-8\n")

        let fromStdin = await CLIHarness.run(["--html"], stdin: Data([0x23, 0x20, 0xFF, 0x0A]))
        #expect(fromStdin.status == 65)
        #expect(fromStdin.stderr == "peep: stdin: not valid UTF-8\n")
    }

    @Test("one bad input among several prints nothing")
    func badInputAmongSeveral() async throws {
        let folder = try TempFolder()
        let result = await CLIHarness.run([
            "--fragment", try folder.fixture("hello.md"), folder.path("missing.md"),
        ])
        #expect(result.status == 66)
        #expect(result.stdout.isEmpty)
    }

    @Test("a failing standard input read exits 66")
    func standardInputReadFailure() async {
        let result = await CLIHarness.run(["--html"], stdinError: CocoaError(.fileReadUnknown))
        #expect(result.status == 66)
        #expect(result.stderr.hasPrefix("peep: stdin: "))
    }

    @Test("with no FILE and a terminal on standard input, Peep prints usage instead of waiting")
    func terminalStandardInput() async {
        for flags in [[], ["--html"]] {
            let result = await CLIHarness.run(flags, stdinIsTerminal: true)
            #expect(result.status == 64)
            #expect(result.stdout.isEmpty)
            #expect(result.stderr.hasPrefix("peep: no FILE given and standard input is a terminal\nUsage: peep"))
            #expect(result.openedInApp.isEmpty)
        }
    }

    @Test("'-' reads standard input even from a terminal")
    func dashFromTerminal() async {
        let result = await CLIHarness.run(["--html", "-"], stdin: Data("# Typed\n".utf8), stdinIsTerminal: true)
        #expect(result.status == 0)
        #expect(result.stdout.contains("<title>Typed</title>"))
    }

    @Test("'-' twice is a usage error")
    func dashTwice() async {
        let result = await CLIHarness.run(["--fragment", "-", "-"], stdin: "x")
        #expect(result.status == 64)
    }
}
