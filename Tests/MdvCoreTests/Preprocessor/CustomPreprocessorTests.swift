import Darwin
import Foundation
import Testing

@testable import MdvCore

/// The custom preprocessor runner (#56). Serialized: the leak checks count every descriptor
/// the runner holds, so no other run may be in flight.
@Suite("Custom preprocessor", .serialized)
struct CustomPreprocessorTests {
    // MARK: - Contract

    @Test("the document goes in on stdin and the output comes back as text")
    func transformsInput() async throws {
        let fixtures = try PreprocessorFixtures()
        let output = try await fixtures.preprocessor("upcase", limits: .standard)
            .run(input: Data("# Héllo\n".utf8), documentURL: nil)
        #expect(output == "# HÉLLO\n")
    }

    @Test("an empty document runs with stdin closed")
    func emptyInput() async throws {
        let fixtures = try PreprocessorFixtures()
        let output = try await fixtures.preprocessor("upcase", limits: .standard).run(input: Data(), documentURL: nil)
        #expect(output.isEmpty)
    }

    @Test("a large document is streamed through without deadlocking")
    func largeDocument() async throws {
        let fixtures = try PreprocessorFixtures()
        let line = "a line of markdown text, repeated\n"
        let input = String(repeating: line, count: 100_000)  // 3.4 MB, far past a pipe buffer
        var limits = PreprocessorLimits.standard
        limits.timeout = .seconds(30)
        let output = try await fixtures.preprocessor("upcase", limits: limits).run(
            input: Data(input.utf8), documentURL: nil)
        #expect(output == input.uppercased())
    }

    @Test("arguments are passed verbatim, with no shell")
    func argumentsVerbatim() async throws {
        let fixtures = try PreprocessorFixtures()
        let arguments = ["--flag", "two words", "$(touch pwned)", "; rm -rf /", "*", "", "'quoted'"]
        let output = try await fixtures.preprocessor("report", arguments: arguments, limits: .standard)
            .run(input: PreprocessorFixtures.document, documentURL: nil)
        let reported = output.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix("arg=") }.map { String($0.dropFirst(4)) }
        #expect(reported == arguments)
        #expect(!FileManager.default.fileExists(atPath: fixtures.folder.appending(path: "pwned").path))
    }

    @Test("the environment is minimal, with the document's path, and the working directory is its folder")
    func environmentAndWorkingDirectory() async throws {
        let fixtures = try PreprocessorFixtures()
        let folder = fixtures.folder.appending(path: "docs with spaces", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let document = folder.appending(path: "--read me.md")
        try PreprocessorFixtures.document.write(to: document)

        setenv("MDV_TEST_SECRET", "leaked", 1)
        defer { unsetenv("MDV_TEST_SECRET") }
        let output = try await fixtures.preprocessor("report", limits: .standard)
            .run(input: PreprocessorFixtures.document, documentURL: document)
        let lines = output.split(separator: "\n").map(String.init)
        let environment = lines.filter { $0.hasPrefix("env=") }.map { $0.dropFirst(4) }
        let names = Set(environment.compactMap { $0.split(separator: "=", maxSplits: 1).first.map(String.init) })

        // `sh` adds PWD, SHLVL, and `_` itself.
        #expect(
            names.subtracting(["PWD", "SHLVL", "_", "OLDPWD"]) == [
                "HOME", "LANG", "MDV_DOCUMENT_PATH", "PATH", "TMPDIR",
            ])
        #expect(environment.contains("MDV_DOCUMENT_PATH=\(document.path(percentEncoded: false))"))
        #expect(environment.contains("PATH=\(PreprocessorEnvironment.defaultPath)"))
        #expect(environment.contains("LANG=en_US.UTF-8"))
        let realFolder = try #require(realpath(folder.path(percentEncoded: false), nil))
        defer { free(realFolder) }
        #expect(lines.contains("pwd=\(String(cString: realFolder))"))
        #expect(lines.allSatisfy { !$0.hasPrefix("arg=") })
    }

    @Test("without a document file, there is no MDV_DOCUMENT_PATH and the working directory is /")
    func noDocument() async throws {
        let fixtures = try PreprocessorFixtures()
        let output = try await fixtures.preprocessor("report", limits: .standard)
            .run(input: PreprocessorFixtures.document, documentURL: nil)
        #expect(output.contains("pwd=/\n"))
        #expect(!output.contains("MDV_DOCUMENT_PATH"))
    }

    @Test("the script inherits only stdin, stdout, and stderr")
    func inheritsOnlyStandardDescriptors() async throws {
        let fixtures = try PreprocessorFixtures()
        // An open descriptor of the test process (moved above the numbers a shell uses
        // itself) the script must not see.
        let opened = open(fixtures.folder.path, O_RDONLY)
        let decoy = fcntl(opened, F_DUPFD, 200)
        close(opened)
        defer { close(decoy) }
        try #require(decoy >= 200)
        let output = try await fixtures.preprocessor("report", limits: .standard)
            .run(input: PreprocessorFixtures.document, documentURL: nil)
        let descriptors = output.split(separator: "\n").filter { $0.hasPrefix("fd=") }.compactMap {
            Int32($0.dropFirst(3))
        }
        // Besides 0-2, only the shell's own: the glob's listing of /dev/fd and bash's script
        // descriptor (255).
        #expect(Array(descriptors.prefix(3)) == [0, 1, 2])
        #expect(!descriptors.contains(decoy))
        #expect(descriptors.filter { $0 > 2 && $0 != 255 }.count <= 1)
    }

    // MARK: - Configuration

    @Test("the executable must be an absolute path to an executable regular file")
    func validatesExecutable() throws {
        let fixtures = try PreprocessorFixtures()
        let script = try fixtures.script("upcase")
        func problem(_ path: String, _ arguments: [String] = []) -> PreprocessorExecutableError? {
            do {
                _ = try PreprocessorConfiguration(executablePath: path, arguments: arguments)
                return nil
            } catch {
                return error
            }
        }
        #expect(problem("upcase.sh") == .notAbsolute("upcase.sh"))
        #expect(problem("tr") == .notAbsolute("tr"))
        #expect(problem(fixtures.folder.path + "/missing") == .notFound(fixtures.folder.path + "/missing"))
        #expect(problem(fixtures.folder.path(percentEncoded: false)) != nil)
        #expect(problem(script, ["a\0b"]) == .invalidArgument("a\0b"))

        let plain = fixtures.folder.appending(path: "plain.sh").path(percentEncoded: false)
        try Data("#!/bin/sh\n".utf8).write(to: URL(filePath: plain))
        #expect(problem(plain) == .notExecutable(plain))

        let link = fixtures.folder.appending(path: "link").path(percentEncoded: false)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: script)
        let linked = try PreprocessorConfiguration(executablePath: link)
        #expect(linked.executablePath == link)  // stored as given, checked through the link

        let dotted = try PreprocessorConfiguration(executablePath: fixtures.folder.path + "/./x/../upcase.sh")
        #expect(dotted.executablePath == script)
    }

    @Test("an executable removed after configuration fails before anything runs")
    func executableRemoved() async throws {
        let fixtures = try PreprocessorFixtures()
        let preprocessor = try fixtures.preprocessor("upcase")
        try FileManager.default.removeItem(atPath: preprocessor.configuration.executablePath)
        let error = await #expect(throws: PreprocessorError.self) {
            try await preprocessor.run(input: PreprocessorFixtures.document, documentURL: nil)
        }
        #expect(error?.reason == .executableUnavailable(.notFound(preprocessor.configuration.executablePath)))
    }

    @Test("a document over the input limit isn't run")
    func inputTooLarge() async throws {
        let fixtures = try PreprocessorFixtures()
        var limits = PreprocessorFixtures.shortLimits
        limits.maximumInputBytes = 10
        let error = await #expect(throws: PreprocessorError.self) {
            try await fixtures.preprocessor("upcase", limits: limits).run(
                input: Data(repeating: 0x61, count: 11), documentURL: nil)
        }
        #expect(error?.reason == .inputTooLarge(limit: 10))
    }

    @Test("a missing working directory is a launch failure")
    func missingWorkingDirectory() async throws {
        let fixtures = try PreprocessorFixtures()
        let document = fixtures.folder.appending(path: "gone/doc.md")
        let error = await #expect(throws: PreprocessorError.self) {
            try await fixtures.preprocessor("upcase").run(input: PreprocessorFixtures.document, documentURL: document)
        }
        #expect(error?.reason == .launchFailed(errno: ENOENT))
        #expect(PreprocessorDescriptors.openCount == 0)
    }
}
