import Foundation
import Testing

/// Runs the built `mdv` binary: real argument parsing, standard streams, and exit statuses.
/// The in-process suites cover behavior; these check the process boundary.
@Suite("End to end (built binary)")
struct EndToEndTests {
    @Test("piped Markdown prints a page")
    func pipedHTML() throws {
        guard let result = try CLIBinary.run(["--html"], stdin: Data("# Piped\n".utf8)) else { return }
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("<!doctype html>"))
        #expect(result.stdout.contains("<title>Piped</title>"))
    }

    @Test("a relative FILE resolves against the working directory, and -o writes the file")
    func outputFile() throws {
        let folder = try TempFolder()
        try folder.fixture("hello.md")
        guard let result = try CLIBinary.run(["-o", "hello.html", "hello.md"], in: folder.url) else { return }
        #expect(result.status == 0)
        #expect(result.stdout.isEmpty)
        #expect(try folder.contents("hello.html").contains("<title>Hello</title>"))
    }

    @Test("a missing FILE exits 66 with one stderr line and no Swift error dump")
    func missingFile() throws {
        let folder = try TempFolder()
        guard let result = try CLIBinary.run(["--html", "missing.md"], in: folder.url) else { return }
        #expect(result.status == 66)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr == "mdv: missing.md: No such file or directory\n")
    }

    @Test("invalid UTF-8 exits 65")
    func invalidUTF8() throws {
        guard let result = try CLIBinary.run(["--fragment"], stdin: Data([0xC3, 0x28])) else { return }
        #expect(result.status == 65)
        #expect(result.stderr == "mdv: stdin: not valid UTF-8\n")
    }

    @Test("a usage error exits 64")
    func usageError() throws {
        let folder = try TempFolder()
        try folder.fixture("hello.md")
        try folder.fixture("second.md")
        guard let result = try CLIBinary.run(["--html", "hello.md", "second.md"], in: folder.url) else { return }
        #expect(result.status == 64)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("Usage: mdv"))
    }
}
