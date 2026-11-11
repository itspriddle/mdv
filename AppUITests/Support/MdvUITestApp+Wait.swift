import XCTest

/// `mdv --wait` running in the background (#69): started with
/// `MdvUITestApp.startCommandLine(_:)`, it should keep running until its windows close.
@MainActor
final class RunningCommandLine {
    let process: Process
    let arguments: [String]
    private let errorPipe: Pipe

    init(arguments: [String]) throws {
        process = Process()
        process.executableURL = try MdvUITestApp.commandLineTool()
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        errorPipe = Pipe()
        process.standardError = errorPipe
        self.arguments = arguments
        try process.run()
    }

    deinit {
        if process.isRunning {
            process.terminate()
        }
    }

    /// Whether the command exited within `timeout` seconds (spinning the run loop meanwhile).
    func exits(within timeout: TimeInterval) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while process.isRunning, Date.now < deadline {
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.05))
        }
        return !process.isRunning
    }

    /// Whether the command is still running after `seconds` seconds.
    func isStillRunning(after seconds: TimeInterval) -> Bool {
        !exits(within: seconds)
    }

    /// The exit status, once it has exited.
    var status: Int32 { process.terminationStatus }

    /// What it wrote to standard error, once it has exited.
    var stderr: String {
        String(bytes: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

extension MdvUITestApp {
    /// Starts `mdv arguments…` without waiting for it.
    static func startCommandLine(_ arguments: [String]) throws -> RunningCommandLine {
        try RunningCommandLine(arguments: arguments)
    }

    /// Closes `window` with its close button.
    func close(_ window: XCUIElement) {
        window.buttons[XCUIIdentifierCloseWindow].click()
    }
}
