import Foundation

/// Everything `MdvCommand.execute(in:)` touches outside its arguments and the files they name:
/// standard streams and the app. `live` is the real process; tests pass fakes, so the command
/// runs in-process without spawning (`Tests/MdvCLITests`).
public struct CLIEnvironment: Sendable {
    /// Reads all of standard input. Called at most once per run.
    public var readStandardInput: @Sendable () throws -> Data
    /// Whether standard input is a terminal: with no FILE, mdv then prints usage instead of
    /// waiting silently for input (`-` reads it anyway).
    public var standardInputIsTerminal: Bool
    public var standardOutput: any OutputSink
    public var standardError: any OutputSink
    /// Opens documents in the app (`mdv FILE`, #67).
    public var appOpener: any AppOpening

    public init(
        readStandardInput: @escaping @Sendable () throws -> Data,
        standardInputIsTerminal: Bool,
        standardOutput: any OutputSink,
        standardError: any OutputSink,
        appOpener: any AppOpening
    ) {
        self.readStandardInput = readStandardInput
        self.standardInputIsTerminal = standardInputIsTerminal
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.appOpener = appOpener
    }

    /// The real process: its standard streams and `/usr/bin/open`.
    public static var live: CLIEnvironment {
        CLIEnvironment(
            readStandardInput: { try FileHandle.standardInput.readToEnd() ?? Data() },
            standardInputIsTerminal: isatty(STDIN_FILENO) == 1,
            standardOutput: FileHandleSink(.standardOutput),
            standardError: FileHandleSink(.standardError),
            appOpener: OpenCommandAppOpener()
        )
    }

    /// Writes `mdv: <message>` and a newline to standard error. Best effort: there's nowhere
    /// left to report a failure to write it.
    func reportError(_ message: String) {
        try? standardError.write(Data("mdv: \(message)\n".utf8))
    }
}

/// Where output goes: standard output, standard error, or a test's buffer.
public protocol OutputSink: Sendable {
    func write(_ data: Data) throws
}

/// An `OutputSink` over a file handle (the live standard streams).
public struct FileHandleSink: OutputSink {
    private let handle: FileHandle

    public init(_ handle: FileHandle) {
        self.handle = handle
    }

    public func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
    }
}
