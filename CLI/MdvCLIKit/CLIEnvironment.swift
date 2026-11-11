import Foundation
import MdvCore

/// Everything `MdvCommand.execute(in:)` touches outside its arguments and the files they name:
/// standard streams, the app, and the Themes folder. `live` is the real process; tests pass fakes, so the command
/// runs in-process without spawning (`Tests/MdvCLITests`).
public struct CLIEnvironment: Sendable {
    /// Reads standard input to its end, or, given a maximum, until it has read more than that
    /// many bytes (returning at most one more), so `yes | mdv` can't fill memory. Called at
    /// most once per run.
    public var readStandardInput: @Sendable (_ maximumBytes: Int?) throws -> Data
    /// Whether standard input is a terminal: with no FILE, mdv then prints usage instead of
    /// waiting silently for input (`-` reads it anyway).
    public var standardInputIsTerminal: Bool
    public var standardOutput: any OutputSink
    public var standardError: any OutputSink
    /// Opens documents in the app (`mdv FILE`, #67).
    public var appOpener: any AppOpening
    /// Where `custom:` themes are read from (#64); `nil` reads none. Live:
    /// `ThemeResolver.themesFolder(environment:)`. Tests pass a temp folder or nil, never the
    /// reader's folder.
    public var themesFolder: URL?
    /// The bounds on each `--preprocessor` run (#66): the app's, `.standard`. Tests pass shorter
    /// ones.
    public var preprocessorLimits: PreprocessorLimits
    /// Whether `SIGINT`, `SIGTERM`, and `SIGHUP` cancel a `--preprocessor` run and then end the
    /// process (`InterruptCancellation`). Live only: in-process tests leave the test runner's
    /// signals alone.
    public var cancelsOnInterrupt: Bool

    public init(
        readStandardInput: @escaping @Sendable (_ maximumBytes: Int?) throws -> Data,
        standardInputIsTerminal: Bool,
        standardOutput: any OutputSink,
        standardError: any OutputSink,
        appOpener: any AppOpening,
        themesFolder: URL? = nil,
        preprocessorLimits: PreprocessorLimits = .standard,
        cancelsOnInterrupt: Bool = false
    ) {
        self.readStandardInput = readStandardInput
        self.standardInputIsTerminal = standardInputIsTerminal
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.appOpener = appOpener
        self.themesFolder = themesFolder
        self.preprocessorLimits = preprocessorLimits
        self.cancelsOnInterrupt = cancelsOnInterrupt
    }

    /// The real process: its standard streams, the app (`WorkspaceAppOpener`), and the reader's Themes folder.
    public static var live: CLIEnvironment {
        CLIEnvironment(
            readStandardInput: { try readStandardInput(FileHandle.standardInput, maximumBytes: $0) },
            standardInputIsTerminal: isatty(STDIN_FILENO) == 1,
            standardOutput: FileHandleSink(.standardOutput),
            standardError: FileHandleSink(.standardError),
            appOpener: WorkspaceAppOpener(),
            themesFolder: ThemeResolver.themesFolder(environment: ProcessInfo.processInfo.environment),
            cancelsOnInterrupt: true
        )
    }

    /// Reads `handle` to its end, or until it has read more than `maximumBytes`.
    static func readStandardInput(_ handle: FileHandle, maximumBytes: Int?) throws -> Data {
        guard let maximumBytes else {
            return try handle.readToEnd() ?? Data()
        }
        var data = Data()
        while data.count <= maximumBytes,
            let chunk = try handle.read(upToCount: min(1 << 16, maximumBytes + 1 - data.count)), !chunk.isEmpty
        {
            data.append(chunk)
        }
        return data
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
