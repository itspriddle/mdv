import Foundation
import MdvCore

/// Everything `MdvCommand.execute(in:)` touches outside its arguments and the files they name:
/// standard streams, the app, and the Themes folder. `live` is the real process; tests pass fakes, so the command
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
        readStandardInput: @escaping @Sendable () throws -> Data,
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

    /// The real process: its standard streams, `/usr/bin/open`, and the reader's Themes folder.
    public static var live: CLIEnvironment {
        CLIEnvironment(
            readStandardInput: { try FileHandle.standardInput.readToEnd() ?? Data() },
            standardInputIsTerminal: isatty(STDIN_FILENO) == 1,
            standardOutput: FileHandleSink(.standardOutput),
            standardError: FileHandleSink(.standardError),
            appOpener: OpenCommandAppOpener(),
            themesFolder: ThemeResolver.themesFolder(environment: ProcessInfo.processInfo.environment),
            cancelsOnInterrupt: true
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
