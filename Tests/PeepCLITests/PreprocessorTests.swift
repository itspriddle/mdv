import Darwin
import Foundation
import MdvCore
import Testing

@testable import MdvCLIKit

/// `--preprocessor` and `--preprocessor-arg` (#66): MdvCore's runner on request, with its
/// contract and limits, failing loudly. Scripts are `Fixtures/preprocessors` (copies of
/// MdvCoreTests' fixtures).
@Suite("Preprocessor")
struct PreprocessorTests {
    /// Short limits so misbehaving scripts cost a fraction of a second each.
    static let shortLimits = PreprocessorLimits(
        timeout: .milliseconds(400),
        terminationGracePeriod: .milliseconds(100),
        maximumInputBytes: 1024 * 1024,
        maximumOutputBytes: 64 * 1024,
        maximumErrorBytes: 1024
    )

    // MARK: Running

    @Test("--preprocessor renders the program's output for a file")
    func success() async throws {
        let folder = try TempFolder()
        let document = try folder.file("doc.md", "# Title\n\nSome *text*.\n")
        let script = try Self.script("upcase", in: folder)
        let result = await CLIHarness.run(["--fragment", "--preprocessor", script, document])
        #expect(result.status == 0)
        #expect(result.stdout.contains(">TITLE</h1>"))
        #expect(result.stdout.contains("<em>TEXT</em>"))
        #expect(result.stderr.isEmpty)
    }

    @Test("arguments are passed as given; a file gets MDV_DOCUMENT_PATH and its folder")
    func argumentsAndEnvironment() async throws {
        let folder = try TempFolder()
        let document = try folder.file("doc.md", "ignored\n")
        let script = try Self.script("report", in: folder)
        let arguments = ["--flag", "two words", "$HOME", "-"]
        let result = await CLIHarness.run(
            ["--fragment", "--preprocessor", script] + arguments.flatMap { ["--preprocessor-arg", $0] } + [document])
        #expect(result.status == 0)
        let lines = Self.lines(result.stdout)
        #expect(lines.filter { $0.hasPrefix("arg=") } == arguments.map { "arg=\($0)" })
        let realFolder = try #require(realpath(folder.url.path, nil))
        defer { free(realFolder) }
        #expect(lines.contains("pwd=\(String(cString: realFolder))"))
        #expect(lines.contains("env=MDV_DOCUMENT_PATH=\(document)"))
    }

    @Test("standard input gets no MDV_DOCUMENT_PATH and runs in /")
    func standardInput() async throws {
        let folder = try TempFolder()
        let script = try Self.script("report", in: folder)
        let result = await CLIHarness.run(["--fragment", "--preprocessor", script], stdin: Data("x\n".utf8))
        #expect(result.status == 0)
        let lines = Self.lines(result.stdout)
        #expect(lines.contains("pwd=/"))
        #expect(!lines.contains { $0.hasPrefix("env=MDV_DOCUMENT_PATH=") })
    }

    @Test("standard input is the document's bytes on the program's stdin")
    func standardInputContent() async throws {
        let folder = try TempFolder()
        let script = try Self.script("upcase", in: folder)
        let result = await CLIHarness.run(["--fragment", "--preprocessor", script], stdin: Data("# piped\n".utf8))
        #expect(result.status == 0)
        #expect(result.stdout.contains(">PIPED</h1>"))
    }

    @Test("without --preprocessor nothing runs, even when the document asks")
    func optInOnly() async {
        let result = await CLIHarness.run(
            ["--fragment"], stdin: Data("---\nmdv:\n  preprocessor: /bin/echo\n---\n# plain\n".utf8))
        #expect(result.status == 0)
        #expect(result.stdout.contains(">plain</h1>"))
    }

    // MARK: Failures

    @Test("a non-zero exit fails with the status and the stderr tail, and prints no HTML")
    func nonZeroExit() async throws {
        let folder = try TempFolder()
        let document = try folder.file("doc.md", "# Title\n")
        let script = try Self.script("fail", in: folder)
        let result = await CLIHarness.run(["--html", "--preprocessor", script, document])
        #expect(result.status == 70)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr == "mdv: \(document): The preprocessor exited with status 3.\nsomething went wrong\n")
    }

    @Test("a script that hangs is stopped at the timeout, with nothing left running")
    func timeout() async throws {
        let folder = try TempFolder()
        let document = try folder.file("doc.md", "# Title\n")
        let script = try Self.script("fork-child", in: folder)
        let pidFile = folder.path("pids")
        let result = await CLIHarness.run(
            ["--html", "--preprocessor", script, "--preprocessor-arg", pidFile, document],
            preprocessorLimits: Self.shortLimits)
        #expect(result.status == 70)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("The preprocessor didn’t finish within 0.4 seconds."))
        let pids = try await Self.pids(in: pidFile)
        #expect(pids.count == 2)
        #expect(try await Self.processesGone(pids))
    }

    @Test("a script that ignores SIGTERM is killed at the timeout")
    func timeoutIgnoringTerm() async throws {
        let folder = try TempFolder()
        let script = try Self.script("hang", in: folder)
        let pidFile = folder.path("pid")
        let result = await CLIHarness.run(
            ["--fragment", "--preprocessor", script, "--preprocessor-arg", pidFile],
            stdin: Data("x".utf8), preprocessorLimits: Self.shortLimits)
        #expect(result.status == 70)
        #expect(try await Self.processesGone(try await Self.pids(in: pidFile)))
    }

    @Test("too much output fails with the limit")
    func oversizeOutput() async throws {
        let folder = try TempFolder()
        let script = try Self.script("huge-output", in: folder)
        let result = await CLIHarness.run(
            ["--fragment", "--preprocessor", script], stdin: Data("x".utf8), preprocessorLimits: Self.shortLimits)
        #expect(result.status == 70)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("The preprocessor wrote more than 64 KB."))
    }

    @Test("a missing program fails without running; a relative path is from the working directory")
    func missingProgram() async throws {
        let result = await CLIHarness.run(
            ["--fragment", "--preprocessor", "no-such-preprocessor"], stdin: Data("x".utf8))
        let expected = FileManager.default.currentDirectoryPath + "/no-such-preprocessor"
        #expect(result.status == 70)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("stdin: The preprocessor can’t run: “\(expected)” doesn’t exist."))
    }

    @Test("one failing input among several fragments leaves no output")
    func failingSecondInput() async throws {
        let folder = try TempFolder()
        let first = try folder.file("a.md", "# A\n")
        let script = try Self.script("fail", in: folder)
        let result = await CLIHarness.run(["--fragment", "--preprocessor", script, first, first])
        #expect(result.status == 70)
        #expect(result.stdout.isEmpty)
    }

    @Test("control characters in the stderr tail are escaped; line breaks and tabs are kept")
    func stderrTailIsTerminalSafe() {
        let error = PreprocessorError(.exited(status: 1), standardError: "bad\u{1B}[31m\tline\r\nnext\n")
        let failure = PreprocessorOptions.failure("doc.md", error)
        #expect(failure.message == "doc.md: The preprocessor exited with status 1.\nbad\\u{1B}[31m\tline\nnext")
        #expect(failure.status == 70)
    }

    // MARK: Usage

    @Test(
        "preprocessor flags need HTML output, and --preprocessor-arg needs --preprocessor",
        arguments: [
            ["--preprocessor", "/bin/cat", "doc.md"],
            ["--html", "--preprocessor-arg", "x", "doc.md"],
            ["--html", "--preprocessor", "", "doc.md"],
        ])
    func usage(_ arguments: [String]) async {
        let result = await CLIHarness.run(arguments)
        #expect(result.status == 64)
        #expect(result.stdout.isEmpty)
        #expect(result.openedInApp.isEmpty)
    }

    @Test("--preprocessor-arg takes values that look like options")
    func dashArgument() async throws {
        let folder = try TempFolder()
        let script = try Self.script("report", in: folder)
        let result = await CLIHarness.run(
            ["--fragment", "--preprocessor", script, "--preprocessor-arg", "--html", "--preprocessor-arg", "-o"],
            stdin: Data("x".utf8))
        #expect(result.status == 0)
        #expect(Self.lines(result.stdout).filter { $0.hasPrefix("arg=") } == ["arg=--html", "arg=-o"])
    }

    // MARK: The built binary

    @Test("end to end: a relative --preprocessor path runs from the working directory")
    func endToEnd() throws {
        let folder = try TempFolder()
        try folder.file("doc.md", "# Title\n")
        _ = try Self.script("upcase", in: folder)
        guard
            let result = try CLIBinary.run(
                ["--fragment", "--preprocessor", "upcase.sh", "doc.md"], in: folder.url)
        else { return }
        #expect(result.status == 0)
        #expect(result.stdout.contains(">TITLE</h1>"))
    }

    @Test("end to end: SIGINT stops the script and its children, then ends mdv with SIGINT")
    func interrupt() async throws {
        let folder = try TempFolder()
        let document = try folder.file("doc.md", "# Title\n")
        let script = try Self.script("fork-child", in: folder)
        let pidFile = folder.path("pids")
        let binary = CLIBinary.url
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            Issue.record("mdv binary not found at \(binary.path); set MDV_CLI_BINARY")
            return
        }
        let outputPath = folder.path("stdout")
        let arguments = ["--html", "--preprocessor", script, "--preprocessor-arg", pidFile, document]
        var environment = ProcessInfo.processInfo.environment
        environment["MDV_THEMES_FOLDER"] = folder.path("no-themes")
        // The run's deadline is at least this long after the spawn, so mdv ending sooner than
        // that proves the signal stopped it, however starved the runner (on CI's macOS 26 this
        // test once took 19 s). Only a debug build reads the variable: against a release
        // binary (`MDV_CLI_BINARY`) the timeout is 5 s and this check proves less.
        let timeout: Duration = .seconds(60)
        environment["MDV_TEST_PREPROCESSOR_TIMEOUT"] = "60"
        let start = ContinuousClock.now
        // Not `Process`: a test runner (CI's) may start with SIGINT ignored, and mdv rightly
        // keeps an inherited SIG_IGN.
        let pid = try DefaultSignalProcess.spawn(
            binary.path, arguments: arguments, environment: environment, stdout: outputPath,
            stderr: folder.path("stderr"))
        let interruption = await DefaultSignalProcess.signal(
            SIGINT, pid, whenFileAppears: pidFile, start: start, limit: timeout + .seconds(10))

        let stderr = (try? String(contentsOfFile: folder.path("stderr"), encoding: .utf8)) ?? ""
        let status = interruption.status
        #expect(!interruption.exitedBeforeSignal, "mdv ended before SIGINT (\(status)); stderr: \(stderr)")
        let pids = try #require(interruption.pids, "no pid file at \(pidFile)")
        #expect(pids.count == 2)
        #expect(status.signal == SIGINT, "ended by SIGINT (\(status)); stderr: \(stderr)")
        #expect(interruption.elapsed < timeout, "stopped by SIGINT, not the timeout")
        #expect(stderr.isEmpty, "stderr: \(stderr)")
        #expect((try? Data(contentsOf: URL(filePath: outputPath))) ?? Data() == Data())
        #expect(try await Self.processesGone(pids))
    }

    // MARK: Helpers

    /// Copies fixture script `name` (without `.sh`) into `folder`, executable.
    static func script(_ name: String, in folder: TempFolder) throws -> String {
        let source = try #require(
            Bundle.module.url(forResource: name, withExtension: "sh", subdirectory: "Fixtures/preprocessors"))
        let destination = folder.url.appending(path: "\(name).sh")
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination.path
    }

    /// The report script's lines from a rendered fragment (one paragraph, soft breaks).
    static func lines(_ fragment: String) -> [String] {
        fragment.replacing("<p>", with: "").replacing("</p>", with: "").split(separator: "\n").map(String.init)
    }

    /// The pids a script wrote to `path`, waiting up to 4 s for it to appear.
    static func pids(in path: String) async throws -> [pid_t] {
        for _ in 0..<400 {
            if let text = try? String(contentsOfFile: path, encoding: .utf8), text.hasSuffix("\n") {
                return text.split(whereSeparator: \.isWhitespace).compactMap { pid_t($0) }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("no pid file at \(path)")
        return []
    }

    /// Whether every pid (the first is also the script's process group) is gone, waiting up to
    /// 2 s for launchd to reap orphans.
    static func processesGone(_ pids: [pid_t]) async throws -> Bool {
        for _ in 0..<200 {
            let groupGone = pids.first.map { killpg($0, 0) != 0 && errno == ESRCH } ?? true
            let pidsGone = pids.allSatisfy { kill($0, 0) != 0 && errno == ESRCH }
            if groupGone, pidsGone { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
