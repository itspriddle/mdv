import Foundation
import Testing

/// Every `peep` command in the README's `sh` blocks works (#72). Examples that print or write HTML
/// run against the built binary; examples that open the app run in-process with a recording
/// opener, so they parse, pass their checks, and send the request the README describes. The
/// files an example names are made in a temp folder (README.md is the real README).
@Suite("README examples")
struct ReadmeExampleTests {
    static let readme: String = (try? String(contentsOf: ReadmeExamples.readmeURL, encoding: .utf8)) ?? ""
    static let parsed = ReadmeExamples.examples(in: readme)

    @Test("the README's sh blocks have Peep examples, all in a form this test reads")
    func examplesFound() {
        #expect(!Self.readme.isEmpty, "README.md not found at \(ReadmeExamples.readmeURL.path)")
        #expect(Self.parsed.unsupported.isEmpty, "Examples this test can't read: \(Self.parsed.unsupported)")
        #expect(Self.parsed.examples.contains { $0.isHeadless })
        #expect(Self.parsed.examples.contains { !$0.isHeadless })
    }

    @Test("examples that render HTML work with the built binary", arguments: parsed.examples.filter(\.isHeadless))
    func headless(example: ReadmeExample) throws {
        let folder = try Self.folder(for: example)
        guard
            let result = try CLIBinary.run(
                example.arguments, stdin: Data((example.standardInput ?? "").utf8), in: folder.url)
        else { return }
        #expect(result.status == 0, "\(example): \(result.stderr)")
        #expect(result.stderr.isEmpty, "\(example)")
        if let output = Self.outputFile(of: example) {
            #expect(result.stdout.isEmpty, "\(example)")
            #expect(try folder.contents(output).hasPrefix("<!doctype html>"), "\(example)")
        } else {
            #expect(!result.stdout.isEmpty, "\(example)")
        }
        if example.arguments.contains("--fragment") {
            #expect(!result.stdout.contains("<html"), "\(example)")
            for input in example.inputFiles {
                #expect(result.stdout.contains(Self.heading(for: input)), "\(example)")
            }
        }
    }

    @Test("examples that open the app send what they say", arguments: parsed.examples.filter { !$0.isHeadless })
    func opensApp(example: ReadmeExample) async throws {
        let folder = try Self.folder(for: example)
        // The in-process harness resolves paths against the package root, so name the temp copies.
        let arguments = example.arguments.map { $0.hasSuffix(".md") ? folder.path($0) : $0 }
        let opener = RecordingAppOpener()
        let result = await CLIHarness.run(
            arguments, stdin: Data((example.standardInput ?? "").utf8), appOpener: opener)
        #expect(result.status == 0, "\(example): \(result.stderr)")
        #expect(result.stdout.isEmpty, "\(example)")
        let request = try #require(result.openedInApp.first, "\(example) opened nothing")
        #expect(request.files.map(\.path) == example.inputFiles.map(folder.path), "\(example)")
        // A pipe into `peep FILE` (without `-`) would be ignored: the README shouldn't show one.
        #expect(request.standardInput == example.standardInput, "\(example)")
        if let theme = Self.value(of: "--theme", in: example) {
            #expect(request.themeID == theme, "\(example)")
        }
        #expect(opener.waits == [example.arguments.contains("--wait")], "\(example)")
    }

    @Test(
        "the completion scripts the README links to are the ones make cli-docs generates",
        .enabled(if: GeneratedCLIDocs.isAvailable))
    func completionScripts() throws {
        let names = ReadmeExamples.completionScriptNames(in: Self.readme)
        #expect(Set(names) == ["_peep", "peep.bash", "peep.fish"])
        let folder = try #require(GeneratedCLIDocs.folder).appending(path: "completions")
        for name in names {
            #expect(FileManager.default.fileExists(atPath: folder.appending(path: name).path), "\(name)")
        }
    }

    // MARK: - Helpers

    /// A temp folder holding the example's inputs: README.md is the real README, any other
    /// `NAME.md` is a page headed with its name.
    private static func folder(for example: ReadmeExample) throws -> TempFolder {
        let folder = try TempFolder()
        for input in example.inputFiles {
            let url = folder.url.appending(path: input)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let contents = input == "README.md" ? readme : "# \(heading(for: input))\n\nExample page.\n"
            try folder.file(input, contents)
        }
        return folder
    }

    private static func heading(for input: String) -> String {
        "Page " + input.replacingOccurrences(of: ".md", with: "")
    }

    /// The file an example writes: `-o FILE` (not `-o -`), or a `> FILE` redirection.
    private static func outputFile(of example: ReadmeExample) -> String? {
        if let output = value(of: "-o", in: example) ?? value(of: "--output", in: example) {
            return output == "-" ? nil : output
        }
        return nil
    }

    private static func value(of option: String, in example: ReadmeExample) -> String? {
        guard let index = example.arguments.firstIndex(of: option), index + 1 < example.arguments.count else {
            return nil
        }
        return example.arguments[index + 1]
    }
}
