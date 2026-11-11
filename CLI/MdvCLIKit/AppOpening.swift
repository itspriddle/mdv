import Foundation

/// What `mdv` without an output flag hands to the app: the files named (absolute URLs, not yet
/// checked) and standard input's Markdown when it was read (no FILE, or `-`).
public struct AppOpenRequest: Equatable, Sendable {
    public var files: [URL]
    public var standardInput: String?

    public init(files: [URL], standardInput: String? = nil) {
        self.files = files
        self.standardInput = standardInput
    }
}

/// Opens documents in the app. `CLIEnvironment.appOpener` holds it, so tests record requests
/// instead of launching anything. Throw `CLIError` (usually `ExitStatus.unavailable`) on failure.
///
/// #67 decides how the app is found and opened, #68 how standard input reaches it, and #69
/// (`--wait`) may make `open` return only when the windows close.
public protocol AppOpening: Sendable {
    func open(_ request: AppOpenRequest, options: AppOpenOptions) async throws(CLIError)
}

/// Today's mechanism: `open -b <bundle id>`, with standard input in a temp file that is never
/// deleted (#68 replaces this).
public struct OpenCommandAppOpener: AppOpening {
    public init() {}

    public func open(_ request: AppOpenRequest, options: AppOpenOptions) async throws(CLIError) {
        var paths = request.files.map(\.path)
        if let markdown = request.standardInput {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("mdv-stdin-\(UUID().uuidString).md")
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                throw CLIError(
                    "couldn't save standard input for the app: \(error.localizedDescription)",
                    status: ExitStatus.unavailable)
            }
            paths.append(url.path)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", MdvCommand.appBundleIdentifier, "--"] + paths
        do {
            try process.run()
        } catch {
            throw CLIError("couldn't open the app: \(error.localizedDescription)", status: ExitStatus.unavailable)
        }
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw CLIError(
                "couldn't open the app (open exited with status \(process.terminationStatus))",
                status: ExitStatus.unavailable)
        }
    }
}
