import Darwin
import Foundation

/// Why a custom preprocessor run failed (#56): a reason, plus the tail of the script's stderr
/// (at most `PreprocessorLimits.maximumErrorBytes`, decoded leniently), for the reader.
/// Cancellation is not a `PreprocessorError`; it throws `CancellationError`.
public struct PreprocessorError: Error, Sendable, Equatable, CustomStringConvertible {
    public enum Reason: Sendable, Equatable {
        /// The document is larger than `maximumInputBytes`; nothing ran.
        case inputTooLarge(limit: Int)
        /// The configured executable is no longer usable; nothing ran.
        case executableUnavailable(PreprocessorExecutableError)
        /// `posix_spawn` (or creating pipes) failed, e.g. the working directory is gone.
        case launchFailed(errno: Int32)
        /// The script hadn't exited after `timeout`.
        case timedOut(Duration)
        /// The script wrote more than `maximumOutputBytes` to stdout.
        case outputTooLarge(limit: Int)
        /// The script exited with a non-zero status.
        case exited(status: Int32)
        /// The script was killed by a signal (a crash, or someone else's `kill`).
        case signaled(Int32)
        /// stdout wasn't valid UTF-8.
        case outputNotUTF8
        /// stdout contained a NUL byte.
        case outputContainsNUL
    }

    public let reason: Reason
    /// The end of the script's stderr; empty when it wrote none (or never ran).
    public let standardError: String

    public init(_ reason: Reason, standardError: String = "") {
        self.reason = reason
        self.standardError = standardError
    }

    /// One sentence for the reader, without the stderr tail.
    public var message: String {
        switch reason {
        case .inputTooLarge(let limit):
            "The document is larger than the preprocessor limit (\(Self.size(limit)))."
        case .executableUnavailable(let problem):
            "The preprocessor can’t run: \(problem)"
        case .launchFailed(let code):
            "The preprocessor couldn’t start: \(String(cString: strerror(code)))."
        case .timedOut(let timeout):
            "The preprocessor didn’t finish within \(Self.seconds(timeout))."
        case .outputTooLarge(let limit):
            "The preprocessor wrote more than \(Self.size(limit))."
        case .exited(let status):
            "The preprocessor exited with status \(status)."
        case .signaled(let signal):
            "The preprocessor was stopped by signal \(signal) (\(Self.signalName(signal)))."
        case .outputNotUTF8:
            "The preprocessor’s output isn’t UTF-8 text."
        case .outputContainsNUL:
            "The preprocessor’s output contains a NUL byte."
        }
    }

    public var description: String {
        standardError.isEmpty ? message : "\(message)\n\(standardError)"
    }

    private static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }

    private static func seconds(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return seconds.formatted(.number.precision(.fractionLength(0...1))) + (seconds == 1 ? " second" : " seconds")
    }

    private static func signalName(_ signal: Int32) -> String {
        guard signal > 0, signal < NSIG, let name = strsignal(signal) else { return "unknown signal" }
        return String(cString: name)
    }
}
