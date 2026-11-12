import AppKit
import Foundation
import PeepCore

/// What `peep` without an output flag hands to the app: the files named (absolute URLs, checked
/// readable by `PeepCommand.openInApp(in:)`), standard input's Markdown when it was read (no
/// FILE, or `-`), and the windows' options.
public struct AppOpenRequest: Equatable, Sendable {
    public var files: [URL]
    public var standardInput: String?
    /// `--theme`: the windows' View > Theme pick (bundled ids lowercased).
    public var themeID: String?

    public init(files: [URL], standardInput: String? = nil, themeID: String? = nil) {
        self.files = files
        self.standardInput = standardInput
        self.themeID = themeID
    }
}

/// Opens documents in the app. `CLIEnvironment.appOpener` holds it, so tests record requests
/// instead of launching anything. Throw `CLIError` (usually `ExitStatus.unavailable`) on failure.
///
/// With `options.wait` (#69), `open` returns
/// only once the windows it opened are closed or the app quits (`WindowsClosedWaiter`).
public protocol AppOpening: Sendable {
    func open(_ request: AppOpenRequest, options: AppOpenOptions) async throws(CLIError)
}

/// The live opener (#67): finds the app (`AppLocator`) and gives Launch Services an Open
/// Documents Apple Event carrying the files and `AppOpenParameters` (`AppOpenEvent`). Launch
/// Services launches the app with it, or sends it to the running app, and activates the app, as
/// Finder's open does. See docs/VISION.md, "CLI to app".
///
/// Standard input (#68) goes in a private handoff file (`StandardInputHandoff`), last among the
/// event's files; the app recognizes it by its shape, deletes it once read, and shows it as an
/// untitled window. This opener deletes it if the event never got to the app.
public struct WorkspaceAppOpener: AppOpening {
    /// Environment variables passed on to an app this opener launches: `LaunchTiming`'s, so
    /// `scripts/measure-cold-open -c` can time `peep FILE`. They only make the app report timings.
    static let forwardedEnvironment = ["PEEP_LAUNCH_TIMING", "PEEP_LAUNCH_TIMING_LOG"]

    private let locator: AppLocator
    /// Where standard input's handoff folder is made (`temporaryFolder(environment:)`).
    private let temporaryFolder: URL

    public init(
        locator: AppLocator = .live,
        temporaryFolder: URL = Self.temporaryFolder(environment: ProcessInfo.processInfo.environment)
    ) {
        self.locator = locator
        self.temporaryFolder = temporaryFolder
    }

    public func open(_ request: AppOpenRequest, options: AppOpenOptions) async throws(CLIError) {
        let app = try locator.locate()
        var files = request.files
        var handoff: URL?
        if let markdown = request.standardInput {
            let file = try handOff(markdown)
            files.append(file)
            handoff = file
        }
        let waiter: WindowsClosedWaiter?
        let processIdentifier: pid_t?
        do {
            // Registered before the event goes, so a window closed at once isn't missed.
            waiter = options.wait ? try WindowsClosedWaiter() : nil
            let parameters = AppOpenParameters(themeID: request.themeID, waitToken: waiter?.token)
            processIdentifier = try await Self.deliver(files: files, parameters: parameters, to: app)
        } catch {
            // The app never got the event, so nothing else will delete the handoff.
            if let handoff {
                StandardInputHandoff.remove(handoff)
            }
            throw error
        }
        if let waiter {
            // The app's process too, so a quit or crash ends the wait.
            await waiter.wait(forProcess: processIdentifier ?? AppLocator.runningProcess(of: app))
        }
    }

    /// Sends the open event to `app` (`AppLocator.runningTarget(for:)`) and returns the process
    /// that got it, when known.
    private static func deliver(
        files: [URL], parameters: AppOpenParameters, to app: URL
    ) async throws(CLIError) -> pid_t? {
        do {
            switch AppLocator.runningTarget(for: app) {
            case .running(let processIdentifier):
                try send(files: files, parameters: parameters, to: processIdentifier)
                return processIdentifier
            case .launchServices(let createsNewInstance):
                do {
                    return try await openWithLaunchServices(
                        app, files: files, parameters: parameters, createsNewInstance: createsNewInstance)
                } catch {
                    // A sandboxed caller (the UI test runner, and so the CLI it runs) can't give
                    // the app access to the files, and Launch Services refuses the whole open.
                    // The app isn't sandboxed: a running copy can take the event directly.
                    guard let running = AppLocator.runningProcess(of: app) else {
                        throw error
                    }
                    try send(files: files, parameters: parameters, to: running)
                    return running
                }
            }
        } catch {
            throw CLIError(
                "couldn't open \(app.path(percentEncoded: false)): \(error.localizedDescription)",
                status: ExitStatus.unavailable)
        }
    }

    /// Launch Services: launches `app` with the event as its first event, or sends it to the
    /// running copy, and activates the app (no Automation prompt: this is Finder's path).
    /// Returns the app's process id.
    private static func openWithLaunchServices(
        _ app: URL, files: [URL], parameters: AppOpenParameters, createsNewInstance: Bool
    ) async throws -> pid_t? {
        let bundleIdentifier = Bundle(url: app)?.bundleIdentifier ?? PeepCommand.appBundleIdentifier
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.appleEvent = AppOpenEvent.make(
            files: files, parameters: parameters, target: NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier))
        configuration.activates = true
        configuration.createsNewApplicationInstance = createsNewInstance
        let environment = ProcessInfo.processInfo.environment.filter { forwardedEnvironment.contains($0.key) }
        if !environment.isEmpty {
            configuration.environment = environment
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<pid_t?, any Error>) in
            NSWorkspace.shared.openApplication(at: app, configuration: configuration) { running, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: running?.processIdentifier)
                }
            }
        }
    }

    /// Sends Peep's own open event (`AppOpenEvent.Kind.direct`) straight to the copy of the app at
    /// our path, when Launch Services would pick another copy with the same bundle id (a
    /// development build next to an installed one) or refuses a sandboxed caller.
    ///
    /// No reply is awaited: the app doesn't handle Apple Events while a modal alert runs (the
    /// first-run default viewer offer, an open error), so waiting blocked `peep` until the alert
    /// closed or the send timed out (exit 69) for files the app then opened anyway. Errors that
    /// need no reply (no such process, Apple Events not permitted) still throw.
    private static func send(files: [URL], parameters: AppOpenParameters, to processIdentifier: pid_t) throws {
        let event = AppOpenEvent.make(
            files: files, parameters: parameters, target: NSAppleEventDescriptor(processIdentifier: processIdentifier),
            kind: .direct)
        _ = try event.sendEvent(options: [.noReply], timeout: 10)
        NSRunningApplication(processIdentifier: processIdentifier)?.activate()
    }

    /// Writes standard input to a private handoff file the app deletes once it has read it
    /// (`StandardInputHandoff`, #68).
    private func handOff(_ markdown: String) throws(CLIError) -> URL {
        do {
            return try StandardInputHandoff.write(Data(markdown.utf8), inFolder: temporaryFolder)
        } catch {
            throw CLIError(
                "couldn't save standard input for the app in \(temporaryFolder.path(percentEncoded: false)): "
                    + error.localizedDescription,
                status: ExitStatus.unavailable)
        }
    }

    /// Where handoff folders go: `TMPDIR` when it is an absolute path (the per-user temp folder
    /// in a login shell), else Foundation's temporary directory. The folder needn't be private:
    /// each handoff is in its own new folder that only this user can open.
    public static func temporaryFolder(environment: [String: String]) -> URL {
        if let path = environment["TMPDIR"], path.hasPrefix("/") {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return FileManager.default.temporaryDirectory
    }
}

/// Finds the Peep.app to open (#67): the app that contains this executable
/// (`Peep.app/Contents/Helpers/peep`, through any symlinks, #70), so a development build's CLI
/// never opens another installed copy; else, run outside a bundle (`swift run peep`), the app
/// Launch Services knows by `PeepCommand.appBundleIdentifier`.
public struct AppLocator: Sendable {
    /// The real path of the running executable.
    var executablePath: @Sendable () -> String?
    /// Launch Services' app for a bundle id.
    var applicationForBundleIdentifier: @Sendable (String) -> URL?

    public init(
        executablePath: @escaping @Sendable () -> String?,
        applicationForBundleIdentifier: @escaping @Sendable (String) -> URL?
    ) {
        self.executablePath = executablePath
        self.applicationForBundleIdentifier = applicationForBundleIdentifier
    }

    public static let live = AppLocator(
        executablePath: { Bundle.main.executableURL?.resolvingSymlinksInPath().path(percentEncoded: false) },
        applicationForBundleIdentifier: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) })

    /// The app to open, or `ExitStatus.unavailable` when there is none.
    public func locate() throws(CLIError) -> URL {
        if let path = executablePath(), let app = Self.containingApp(ofExecutableAt: path) {
            return app
        }
        if let app = applicationForBundleIdentifier(PeepCommand.appBundleIdentifier) {
            return app
        }
        throw CLIError(
            "can't find Peep.app (\(PeepCommand.appBundleIdentifier)); install it, or use --html",
            status: ExitStatus.unavailable)
    }

    /// The `.app` bundle whose `Contents/Helpers` holds the executable at `path` (already
    /// resolved), when its bundle id is Peep's; nil otherwise.
    public static func containingApp(ofExecutableAt path: String) -> URL? {
        let helpers = URL(filePath: path).deletingLastPathComponent()
        let contents = helpers.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard helpers.lastPathComponent == "Helpers", contents.lastPathComponent == "Contents",
            app.pathExtension == "app",
            Bundle(url: app)?.bundleIdentifier == PeepCommand.appBundleIdentifier
        else {
            return nil
        }
        return app
    }

    /// How to reach `app`.
    enum Target: Equatable {
        /// Through Launch Services; `createsNewInstance` when another copy with the same
        /// bundle id is running and this one isn't (Launch Services would pick the other).
        case launchServices(createsNewInstance: Bool)
        /// This copy is running alongside another with the same bundle id: send it the event.
        case running(pid_t)
    }

    /// Launch Services finds a running app by bundle id, not path, so with two copies running it
    /// may pick the wrong one. Only then does the opener go around it.
    static func runningTarget(for app: URL) -> Target {
        target(for: app, running: runningCopies())
    }

    /// The process id of `app` when it is running.
    static func runningProcess(of app: URL) -> pid_t? {
        runningCopies().first { isSameBundle($0.1, app) }?.0
    }

    /// Whether two bundle URLs name the same folder: resolved paths, ignoring a trailing slash
    /// (a bundle URL has one; a URL built from a path may not).
    static func isSameBundle(_ lhs: URL, _ rhs: URL) -> Bool {
        func path(_ url: URL) -> String {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
            return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        return path(lhs) == path(rhs)
    }

    private static func runningCopies() -> [(pid_t, URL)] {
        NSRunningApplication.runningApplications(withBundleIdentifier: PeepCommand.appBundleIdentifier)
            .compactMap { running in running.bundleURL.map { (running.processIdentifier, $0) } }
    }

    /// `runningTarget(for:)`'s decision, given the running copies' process ids and bundle URLs.
    static func target(for app: URL, running copies: [(pid_t, URL)]) -> Target {
        let ours = copies.first { isSameBundle($0.1, app) }
        let others = copies.contains { !isSameBundle($0.1, app) }
        switch (ours, others) {
        case (let ours?, true):
            return .running(ours.0)
        case (nil, true):
            return .launchServices(createsNewInstance: true)
        default:
            return .launchServices(createsNewInstance: false)
        }
    }
}
