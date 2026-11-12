import Foundation

/// A failure the CLI reports as one line on standard error (`mdv: <message>`) plus an exit status.
/// Every failure `MdvCommand.execute(in:)` can hit becomes one of these: no Swift error dumps.
public struct CLIError: Error, Equatable, Sendable {
    public var message: String
    public var status: Int32

    public init(_ message: String, status: Int32) {
        self.message = message
        self.status = status
    }

    /// A usage problem found after parsing (exit 64).
    public static func usage(_ message: String) -> CLIError {
        CLIError(message, status: ExitStatus.usage)
    }

    /// `subject` names the file (`stdin` for standard input); `code` is an `errno` value.
    static func posix(_ subject: String, _ code: Int32, status: Int32) -> CLIError {
        CLIError("\(subject): \(String(cString: strerror(code)))", status: status)
    }
}
