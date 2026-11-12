import XCTest

extension PeepUITestApp {
    /// The CLI embedded in the app under test (`Peep.app/Contents/Helpers/peep`), next to the UI
    /// test runner in the build products folder. Running it opens that app, the one the test
    /// launched (#67).
    static func commandLineTool() throws -> URL {
        // …/Products/Debug/AppUITests-Runner.app/Contents/PlugIns/AppUITests.xctest
        let products = Bundle(for: CommandLineUITests.self).bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let tool = products.appending(path: "Peep.app/Contents/Helpers/peep")
        guard FileManager.default.isExecutableFile(atPath: tool.path(percentEncoded: false)) else {
            throw XCTSkip("No embedded CLI at \(tool.path(percentEncoded: false))")
        }
        return tool
    }

    /// A copy of the fixture `name` in a new temp folder (the caller removes the folder).
    static func temporaryCopy(ofFixture name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-ui-cli-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: (name as NSString).lastPathComponent)
        try FileManager.default.copyItem(at: try Fixtures.url(named: name), to: copy)
        return copy
    }

    /// Runs `peep arguments…` and returns its exit status and standard error. Gives up after 20 s.
    /// Standard input is the file `standardInput` (a file, so a run that stops reading early
    /// can't raise `SIGPIPE` here), else empty; `environment` adds to the runner's.
    @discardableResult
    static func runCommandLine(
        _ arguments: [String], standardInput: URL? = nil, environment: [String: String] = [:]
    ) throws -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = try commandLineTool()
        process.arguments = arguments
        process.standardInput = try standardInput.map { try FileHandle(forReadingFrom: $0) } ?? FileHandle.nullDevice
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        }
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        let deadline = Date.now.addingTimeInterval(20)
        while process.isRunning, Date.now < deadline {
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.05))
        }
        if process.isRunning {
            process.terminate()
            XCTFail("peep \(arguments) didn't exit")
        }
        let stderr = String(bytes: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stderr)
    }

    /// Whether View > Theme > Document's Theme is enabled: it is while the window's View > Theme
    /// pick hides the document's own theme. Opens the menu, looks, and closes it, again until it
    /// reads `expected` (on a loaded machine the item can read stale just after a change, though
    /// the app's state is right); returns what it last read.
    func documentThemeItemIsEnabled(expected: Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(Self.defaultTimeout)
        var result: Bool
        repeat {
            let view = app.menuBars.menuBarItems["View"]
            view.click()
            let submenu = view.menuItems["Theme"]
            submenu.hover()
            let item = submenu.menuItems["useDocumentTheme:"]
            result = item.waitForExistence(timeout: 2) && item.isEnabled
            app.typeKey(.escape, modifierFlags: [])
            app.typeKey(.escape, modifierFlags: [])
        } while result != expected && Date.now < deadline
        return result
    }
}
