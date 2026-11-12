import Foundation
import Testing

/// The built `peep` executable, for end-to-end tests. `swift test` builds it (the test target
/// depends on `PeepCLI`) next to the test bundle; `PEEP_CLI_BINARY` overrides the path.
enum CLIBinary {
    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["PEEP_CLI_BINARY"] {
            return URL(fileURLWithPath: path)
        }
        // The products folder holds the binary. The tests' resource bundle is in it (native
        // build system) or inside the .xctest bundle there (Swift Build).
        var folder = Bundle.module.bundleURL.deletingLastPathComponent()
        var candidate = folder
        while candidate.pathComponents.count > 1 {
            if candidate.pathExtension == "xctest" {
                folder = candidate.deletingLastPathComponent()
                break
            }
            candidate = candidate.deletingLastPathComponent()
        }
        return folder.appending(path: "peep")
    }

    /// Runs the binary with `arguments` in `directory`, feeding `stdin` (closed after), and waits
    /// for it to exit. Records an issue and returns `nil` when the binary is missing.
    /// `themesFolder` is passed as `PEEP_THEMES_FOLDER`; by default a folder that doesn't exist, so
    /// a run never reads the reader's own Themes folder. `environment` adds variables.
    static func run(
        _ arguments: [String], stdin: Data = Data(), in directory: URL? = nil, themesFolder: URL? = nil,
        environment extra: [String: String] = [:]
    ) throws -> CLIResult? {
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            Issue.record("peep binary not found at \(url.path); set PEEP_CLI_BINARY")
            return nil
        }
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        let noThemes = FileManager.default.temporaryDirectory.appending(path: "peep-no-themes-\(UUID().uuidString)")
        var environment = ProcessInfo.processInfo.environment
        environment["PEEP_THEMES_FOLDER"] = (themesFolder ?? noThemes).path
        environment.merge(extra) { _, new in new }
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        try process.run()

        // Read both streams on their own threads so neither pipe fills up and stalls the child.
        let outputData = ReadAll(output.fileHandleForReading)
        let errorData = ReadAll(error.fileHandleForReading)
        try input.fileHandleForWriting.write(contentsOf: stdin)
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        return CLIResult(
            status: process.terminationStatus, standardOutput: outputData.wait(), standardError: errorData.wait())
    }
}

/// Reads a file handle to its end on a background thread.
private final class ReadAll: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private var data = Data()  // Written once on the reading thread before `done` signals.

    init(_ handle: FileHandle) {
        Thread.detachNewThread { [self] in
            data = (try? handle.readToEnd()) ?? Data()
            done.signal()
        }
    }

    func wait() -> Data {
        done.wait()
        return data
    }
}
