import Darwin
import Foundation
import os

/// Runs the reader's own executable on a document before rendering (#56).
///
/// The contract (VISION, security model): the document's bytes on stdin, Markdown as UTF-8 on
/// stdout, exit status 0 for success. The executable gets `configuration.arguments` as its
/// argv (no shell), a minimal environment with the document's path in `MDV_DOCUMENT_PATH`,
/// and the document's folder as its working directory (`PreprocessorEnvironment`). Each run
/// is bounded by `configuration.limits`; a script that hangs, floods output, crashes, or
/// leaves children behind yields a `PreprocessorError` (or `CancellationError`), never a
/// hang, and every process it started in its process group is killed and reaped.
///
/// Opting in is the caller's job: nothing in MdvCore runs a preprocessor unless handed one.
public struct CustomPreprocessor: Sendable {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "mdv", category: "preprocessor")

    public let configuration: PreprocessorConfiguration

    public init(configuration: PreprocessorConfiguration) {
        self.configuration = configuration
    }

    /// Runs the preprocessor on `input` and returns its output.
    ///
    /// The process runs and its pipes are serviced on a dedicated thread, so this never blocks
    /// the cooperative pool. Cancelling the task stops the process group (`SIGTERM`, then
    /// `SIGKILL` after the grace period) and throws `CancellationError` once it is reaped.
    ///
    /// - Parameter documentURL: the document's file, for the environment and working
    ///   directory; `nil` for input without a file.
    public func run(input: Data, documentURL: URL?) async throws -> String {
        try Task.checkCancellation()
        let limits = configuration.limits
        guard input.count <= limits.maximumInputBytes else {
            throw fail(PreprocessorError(.inputTooLarge(limit: limits.maximumInputBytes)))
        }
        do throws(PreprocessorExecutableError) {
            try configuration.validateExecutable()
        } catch {
            throw fail(PreprocessorError(.executableUnavailable(error)))
        }

        let environment = PreprocessorEnvironment(documentURL: documentURL)
        let session = try PreprocessorSession(limits: limits)
        let outcome = try await withTaskCancellationHandler {
            try await Self.onDedicatedThread(priority: Task.currentPriority) {
                () throws(PreprocessorError) -> PreprocessorSession.Outcome? in
                defer { session.finish() }
                if session.isCancelled { return nil }
                let process = try PreprocessorProcess.launch(
                    executable: configuration.executablePath,
                    arguments: configuration.arguments,
                    environment: environment
                )
                return session.drive(process, input: Array(input))
            }
        } onCancel: {
            session.cancel()
        }
        guard let outcome, outcome.stop != .cancelled else { throw CancellationError() }
        do throws(PreprocessorError) {
            return try Self.result(of: outcome, limits: limits)
        } catch {
            throw fail(error)
        }
    }

    private func fail(_ error: PreprocessorError) -> PreprocessorError {
        Self.logger.error(
            "Preprocessor \(configuration.executablePath) failed: \(error.message, privacy: .public)")
        return error
    }

    /// Turns a finished run into text or the error it earned.
    static func result(of outcome: PreprocessorSession.Outcome, limits: PreprocessorLimits) throws(PreprocessorError)
        -> String
    {
        // stderr is for the reader to look at, so it's decoded leniently (U+FFFD for bad bytes).
        // swiftlint:disable:next optional_data_string_conversion
        let errorTail = String(decoding: outcome.errorTail, as: UTF8.self)
        func failure(_ reason: PreprocessorError.Reason) -> PreprocessorError {
            PreprocessorError(reason, standardError: errorTail)
        }
        switch outcome.stop {
        case .timedOut: throw failure(.timedOut(limits.timeout))
        case .outputTooLarge: throw failure(.outputTooLarge(limit: limits.maximumOutputBytes))
        case .cancelled, nil: break
        }
        let signal = outcome.status & 0x7F
        if signal != 0 { throw failure(.signaled(signal)) }
        let status = (outcome.status >> 8) & 0xFF
        if status != 0 { throw failure(.exited(status: status)) }
        if outcome.output.contains(0) { throw failure(.outputContainsNUL) }
        guard let text = String(validating: outcome.output, as: UTF8.self) else { throw failure(.outputNotUTF8) }
        return text
    }

    /// Runs `body` on a new thread at a quality of service matching `priority`, and resumes
    /// with its result.
    private static func onDedicatedThread<Value: Sendable>(
        priority: TaskPriority,
        _ body: @escaping @Sendable () throws(PreprocessorError) -> Value
    ) async throws(PreprocessorError) -> Value {
        let result: Result<Value, PreprocessorError> = await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: Result { () throws(PreprocessorError) in try body() })
            }
            thread.name = "mdv.preprocessor"
            thread.qualityOfService = qualityOfService(for: priority)
            thread.start()
        }
        return try result.get()
    }

    private static func qualityOfService(for priority: TaskPriority) -> QualityOfService {
        if priority >= .userInitiated { return .userInitiated }
        if priority >= .medium { return .default }
        if priority >= .utility { return .utility }
        return .background
    }
}
