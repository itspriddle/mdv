import Foundation
import Testing

@testable import PeepCLIKit
@testable import PeepCore

/// The man page (#71): `ManualPage.finish(_:)` over a saved generate-manual page, and the page
/// `make cli-docs` generated from the current command (when `make test-core` passes it).
@Suite("Man page")
struct ManualPageTests {
    /// generate-manual's output for Peep (ArgumentParser 1.8.2). Refresh it when ArgumentParser is
    /// upgraded: `scripts/generate-cli-docs` leaves it at
    /// `.build/plugins/GenerateManual/outputs/PeepCLI/peep.1`.
    private static func generatedSample() throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: "generate-manual-peep", withExtension: "1", subdirectory: "Fixtures/manual"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func sectionTitles(_ page: String) -> [String] {
        page.components(separatedBy: "\n").filter { $0.hasPrefix(".Sh ") }.map {
            String($0.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
    }

    /// The lines of `title`'s section.
    private static func section(_ title: String, of page: String) -> [String] {
        var lines: [String] = []
        var inside = false
        for line in page.components(separatedBy: "\n") {
            if line.hasPrefix(".Sh ") {
                inside = line.contains(title)
                continue
            }
            if inside {
                lines.append(line)
            }
        }
        return lines
    }

    // MARK: finish(_:)

    @Test("sections are generated, then hand-written, in mdoc's order")
    func sectionOrder() throws {
        let page = try ManualPage.finish(Self.generatedSample())
        #expect(
            Self.sectionTitles(page) == [
                "NAME", "SYNOPSIS", "DESCRIPTION", "ENVIRONMENT", "FILES", "EXIT STATUS", "EXAMPLES",
                "SECURITY CONSIDERATIONS",
            ])
    }

    @Test("the generated options stay; the help subcommand and its placeholder go")
    func options() throws {
        let sample = try Self.generatedSample()
        #expect(sample.contains(".It Em help"))
        let page = try ManualPage.finish(sample)
        #expect(page.contains(".It Fl -theme Ar NAME"))
        #expect(page.contains(".It Fl h , -help"))
        #expect(!page.contains("subcommand"))
        #expect(!page.contains(".It Em help"))
        // The option list is still balanced.
        let description = Self.section("DESCRIPTION", of: page)
        #expect(description.filter { $0.hasPrefix(".Bl") }.count == description.filter { $0 == ".El" }.count)
    }

    @Test("DESCRIPTION is the overview, not the help's examples and exit statuses")
    func description() throws {
        let description = try Self.section("DESCRIPTION", of: ManualPage.finish(Self.generatedSample()))
        let text = description.joined(separator: " ")
        #expect(text.contains("Opens FILE(s) in Peep."))
        #expect(text.contains("Several FILEs print one after another only with --fragment;"))
        #expect(!text.contains("EXIT STATUS"))
        #expect(!text.contains("peep README.md"))
    }

    @Test("EXIT STATUS lists every ExitStatus entry instead of generate-manual's sentence")
    func exitStatus() throws {
        let page = try ManualPage.finish(Self.generatedSample())
        #expect(!page.contains(".Ex -std"))
        let section = Self.section("EXIT STATUS", of: page)
        for entry in ExitStatus.entries {
            #expect(section.contains(".It \(entry.status)"))
        }
        #expect(section.contains(ExitStatus.interruptNote.replacingOccurrences(of: ". ", with: ".\n")))
    }

    @Test("EXAMPLES has every HelpText example, each as a literal block")
    func examples() throws {
        let section = try Self.section("EXAMPLES", of: ManualPage.finish(Self.generatedSample()))
        for example in HelpText.examples {
            let index = try #require(section.firstIndex(of: example.command))
            #expect(section[index - 1] == ".Bd -literal -offset indent")
        }
    }

    @Test("the hand-written sections name what the code uses")
    func sourcedFromCode() throws {
        let page = try ManualPage.finish(Self.generatedSample())
        #expect(Self.section("ENVIRONMENT", of: page).contains(".It Ev \(ThemeResolver.themesFolderVariable)"))
        #expect(ManualPage.documentPathVariable == PreprocessorEnvironment.documentPathVariable)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let folder = try #require(ThemeResolver.themesFolder(environment: [:])).path(percentEncoded: false)
        let displayed = ManualPage.themesFolderDisplayPath.replacingOccurrences(of: "~/", with: home)
        #expect(folder.hasSuffix("/") ? folder == displayed + "/" : folder == displayed)
        let security = Self.section("SECURITY CONSIDERATIONS", of: page).joined(separator: " ")
        #expect(security.contains("after \(PreprocessorLimits.standard.timeout.components.seconds) seconds"))
    }

    @Test("text is escaped for mdoc, one sentence per line")
    func escaping() {
        #expect(ManualPage.text(#"a\b"#) == #"a\eb"#)
        #expect(ManualPage.text("One. .Two") == "One.\n\\&.Two")
        #expect(ManualPage.text("'quoted") == "\\&'quoted")
    }

    @Test("a page without DESCRIPTION, or without its option list, is a format error")
    func formatErrors() {
        #expect(throws: ManualPage.FormatError.self) {
            try ManualPage.finish(".Dd x\n.Sh NAME\n.Nm peep\n.Sh SYNOPSIS\n.Nm\n")
        }
        #expect(throws: ManualPage.FormatError.self) {
            try ManualPage.finish(".Sh NAME\n.Nm peep\n.Sh SYNOPSIS\n.Nm\n.Sh DESCRIPTION\nText only.\n")
        }
        #expect(throws: ManualPage.FormatError.self) { try ManualPage.finish("no sections") }
    }

    // MARK: The generated page

    @Test("the generated page documents every option of PeepCommand", .enabled(if: GeneratedCLIDocs.isAvailable))
    func everyOption() throws {
        let page = try GeneratedCLIDocs.contents("man/man1/peep.1")
        let options = try #require(try CommandOptions.load())
        #expect(!options.options.isEmpty)
        // `.It Fl o , -output Ar FILE`: `Fl` adds a dash to each name after it.
        let items = page.components(separatedBy: "\n").filter { $0.hasPrefix(".It Fl ") }.map {
            Set($0.split(separator: " ").map(String.init))
        }
        for option in options.options {
            let flags = option.spellings.map { String($0.dropFirst()) }
            let documented = items.contains { item in flags.allSatisfy(item.contains) }
            #expect(documented, "\(option.spellings) isn't in the man page")
        }
        for positional in options.visible where positional.kind == "positional" {
            #expect(page.contains(".It Ar \(positional.valueName ?? "")"))
        }
        #expect(!page.contains("subcommand"))
    }

    @Test("the generated page passes mandoc's linter", .enabled(if: GeneratedCLIDocs.isAvailable))
    func lint() throws {
        let mandoc = URL(fileURLWithPath: "/usr/bin/mandoc")
        try #require(FileManager.default.isExecutableFile(atPath: mandoc.path))
        let page = try #require(GeneratedCLIDocs.folder).appending(path: "man/man1/peep.1")
        let process = Process()
        process.executableURL = mandoc
        process.arguments = ["-T", "lint", "-W", "error", page.path]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
