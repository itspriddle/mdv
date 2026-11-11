import ArgumentParser
import Foundation
import MdvCLIKit
import MdvCore
import Synchronization

/// What one run of `mdv` did: its exit status, both output streams, and what it asked the app to
/// open. `CLIHarness.run` (in-process) and `CLIBinary.run` (the built binary) both return one.
struct CLIResult: Sendable {
    var status: Int32
    var standardOutput: Data
    var standardError: Data
    /// In-process runs only: the app opener's requests, in order.
    var openedInApp: [AppOpenRequest] = []

    /// Decoded output; bytes that are not UTF-8 read as a marker so a test fails visibly.
    var stdout: String { String(bytes: standardOutput, encoding: .utf8) ?? "<not UTF-8>" }
    var stderr: String { String(bytes: standardError, encoding: .utf8) ?? "<not UTF-8>" }
}

/// Runs `MdvCommand` in-process against a fake `CLIEnvironment`: parse as `main()` would (usage
/// errors exit 64 with ArgumentParser's message), then `execute(in:)`.
enum CLIHarness {
    static func run(
        _ arguments: [String],
        stdin: Data = Data(),
        stdinError: (any Error & Sendable)? = nil,
        stdinIsTerminal: Bool = false,
        appOpener: RecordingAppOpener = RecordingAppOpener(),
        failingOutput: (any Error & Sendable)? = nil,
        themesFolder: URL? = nil,
        preprocessorLimits: PreprocessorLimits = .standard
    ) async -> CLIResult {
        let output = CapturedOutput(failingWith: failingOutput)
        let error = CapturedOutput()
        let command: MdvCommand
        do {
            command = try MdvCommand.parse(arguments)
        } catch {
            return CLIResult(
                status: MdvCommand.exitCode(for: error).rawValue,
                standardOutput: Data(),
                standardError: Data((MdvCommand.fullMessage(for: error) + "\n").utf8))
        }
        let environment = CLIEnvironment(
            readStandardInput: {
                if let stdinError { throw stdinError }
                return stdin
            },
            standardInputIsTerminal: stdinIsTerminal,
            standardOutput: output,
            standardError: error,
            appOpener: appOpener,
            themesFolder: themesFolder,
            preprocessorLimits: preprocessorLimits)
        let status = await command.execute(in: environment)
        return CLIResult(
            status: status, standardOutput: output.data, standardError: error.data,
            openedInApp: appOpener.requests)
    }

    static func run(_ arguments: [String], stdin: String) async -> CLIResult {
        await run(arguments, stdin: Data(stdin.utf8))
    }
}

/// An `OutputSink` that keeps what was written, or throws `failure` on every write.
final class CapturedOutput: OutputSink {
    private let buffer = Mutex(Data())
    private let failure: (any Error & Sendable)?

    init(failingWith failure: (any Error & Sendable)? = nil) {
        self.failure = failure
    }

    var data: Data { buffer.withLock { $0 } }

    func write(_ data: Data) throws {
        if let failure { throw failure }
        buffer.withLock { $0.append(data) }
    }
}

/// An `AppOpening` that records requests instead of launching the app, or fails with `failure`.
final class RecordingAppOpener: AppOpening {
    private let recorded = Mutex<[AppOpenRequest]>([])
    private let failure: CLIError?

    init(failingWith failure: CLIError? = nil) {
        self.failure = failure
    }

    private let recordedWaits = Mutex<[Bool]>([])

    var requests: [AppOpenRequest] { recorded.withLock { $0 } }
    /// Each request's `AppOpenOptions.wait` (#69).
    var waits: [Bool] { recordedWaits.withLock { $0 } }

    func open(_ request: AppOpenRequest, options: AppOpenOptions) async throws(CLIError) {
        recorded.withLock { $0.append(request) }
        recordedWaits.withLock { $0.append(options.wait) }
        if let failure { throw failure }
    }
}
