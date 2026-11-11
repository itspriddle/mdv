import XCTest

/// `mdv --wait` running in the background (#69): started with
/// `MdvUITestApp.startCommandLine(_:)`, it should keep running until its windows close.
@MainActor
final class RunningCommandLine {
    let process: Process
    let arguments: [String]
    private let errorPipe: Pipe

    init(arguments: [String], standardInput: URL? = nil, environment: [String: String] = [:]) throws {
        process = Process()
        process.executableURL = try MdvUITestApp.commandLineTool()
        process.arguments = arguments
        process.standardInput = try standardInput.map { try FileHandle(forReadingFrom: $0) } ?? FileHandle.nullDevice
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        }
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
    /// Starts `mdv arguments…` without waiting for it; standard input is the file
    /// `standardInput`, else empty, and `environment` adds to the runner's.
    static func startCommandLine(
        _ arguments: [String], standardInput: URL? = nil, environment: [String: String] = [:]
    ) throws -> RunningCommandLine {
        try RunningCommandLine(arguments: arguments, standardInput: standardInput, environment: environment)
    }

    /// Closes `window`: brings it to the front from the Window menu, then File > Close (⌘W).
    /// Not its close button: another window may cover it (two windows opened at once can land
    /// on the same spot), and XCTest's interruption handling for a covered element then threw
    /// "Can't do regex matching on object 1." on macOS 26.
    func close(_ window: XCUIElement) {
        let title = window.title
        let windowMenu = app.menuBars.menuBarItems["Window"]
        windowMenu.click()
        windowMenu.menuItems[title].click()
        app.typeKey("w", modifierFlags: .command)
    }
}
