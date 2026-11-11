import AppKit
import Foundation
import MdvCore

/// What `mdv` without an output flag hands to the app: the files named (absolute URLs, checked
/// readable by `MdvCommand.openInApp(in:)`), standard input's Markdown when it was read (no
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
/// #68 decides how standard input reaches the app, and #69 (`--wait`) may make `open` return
/// only when the windows close.
public protocol AppOpening: Sendable {
    func open(_ request: AppOpenRequest, options: AppOpenOptions) async throws(CLIError)
}

/// The live opener (#67): finds the app (`AppLocator`) and gives Launch Services an Open
/// Documents Apple Event carrying the files and `AppOpenParameters` (`AppOpenEvent`). Launch
/// Services launches the app with it, or sends it to the running app, and activates the app, as
/// Finder's open does. See docs/VISION.md, "CLI to app".
///
/// Standard input still goes in a temp file that is never deleted (#68 replaces this).
public struct WorkspaceAppOpener: AppOpening {
    /// Environment variables passed on to an app this opener launches: `LaunchTiming`'s, so
    /// `scripts/measure-cold-open -c` can time `mdv FILE`. They only make the app report timings.
    static let forwardedEnvironment = ["MDV_LAUNCH_TIMING", "MDV_LAUNCH_TIMING_LOG"]

    private let locator: AppLocator

    public init(locator: AppLocator = .live) {
        self.locator = locator
    }

    public func open(_ request: AppOpenRequest, options: AppOpenOptions) async throws(CLIError) {
        var files = request.files
        if let markdown = request.standardInput {
            files.append(try Self.saveStandardInput(markdown))
        }
        let app = try locator.locate()
        let parameters = AppOpenParameters(themeID: request.themeID)
        let target = AppLocator.runningTarget(for: app)
        do {
            switch target {
            case .running(let processIdentifier):
                try Self.send(files: files, parameters: parameters, to: processIdentifier)
            case .launchServices(let createsNewInstance):
                do {
                    try await Self.openWithLaunchServices(
                        app, files: files, parameters: parameters, createsNewInstance: createsNewInstance)
                } catch {
                    // A sandboxed caller (the UI test runner, and so the CLI it runs) can't give
                    // the app access to the files, and Launch Services refuses the whole open.
                    // The app isn't sandboxed: a running copy can take the event directly.
                    guard let running = AppLocator.runningProcess(of: app) else {
                        throw error
                    }
                    try Self.send(files: files, parameters: parameters, to: running)
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
    private static func openWithLaunchServices(
        _ app: URL, files: [URL], parameters: AppOpenParameters, createsNewInstance: Bool
    ) async throws {
        let bundleIdentifier = Bundle(url: app)?.bundleIdentifier ?? MdvCommand.appBundleIdentifier
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.appleEvent = AppOpenEvent.make(
            files: files, parameters: parameters, target: NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier))
        configuration.activates = true
        configuration.createsNewApplicationInstance = createsNewInstance
        let environment = ProcessInfo.processInfo.environment.filter { forwardedEnvironment.contains($0.key) }
        if !environment.isEmpty {
            configuration.environment = environment
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Sends mdv's own open event (`AppOpenEvent.Kind.direct`) straight to the copy of the app at
    /// our path, when Launch Services would pick another copy with the same bundle id (a
    /// development build next to an installed one) or refuses a sandboxed caller. AppKit answers
    /// an Open Documents event that doesn't come from Launch Services as a scripting command,
    /// without the app delegate, so it would drop mdv's parameters.
    private static func send(files: [URL], parameters: AppOpenParameters, to processIdentifier: pid_t) throws {
        let event = AppOpenEvent.make(
            files: files, parameters: parameters, target: NSAppleEventDescriptor(processIdentifier: processIdentifier),
            kind: .direct)
        _ = try event.sendEvent(options: [.waitForReply], timeout: 10)
        NSRunningApplication(processIdentifier: processIdentifier)?.activate()
    }

    private static func saveStandardInput(_ markdown: String) throws(CLIError) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdv-stdin-\(UUID().uuidString).md")
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw CLIError(
                "couldn't save standard input for the app: \(error.localizedDescription)",
                status: ExitStatus.unavailable)
        }
        return url
    }
}

/// Finds the mdv.app to open (#67): the app that contains this executable
/// (`mdv.app/Contents/Helpers/mdv`, through any symlinks, #70), so a development build's CLI
/// never opens another installed copy; else, run outside a bundle (`swift run mdv`), the app
/// Launch Services knows by `MdvCommand.appBundleIdentifier`.
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
        if let app = applicationForBundleIdentifier(MdvCommand.appBundleIdentifier) {
            return app
        }
        throw CLIError(
            "can't find mdv.app (\(MdvCommand.appBundleIdentifier)); install it, or use --html",
            status: ExitStatus.unavailable)
    }

    /// The `.app` bundle whose `Contents/Helpers` holds the executable at `path` (already
    /// resolved), when its bundle id is mdv's; nil otherwise.
    public static func containingApp(ofExecutableAt path: String) -> URL? {
        let helpers = URL(filePath: path).deletingLastPathComponent()
        let contents = helpers.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard helpers.lastPathComponent == "Helpers", contents.lastPathComponent == "Contents",
            app.pathExtension == "app",
            Bundle(url: app)?.bundleIdentifier == MdvCommand.appBundleIdentifier
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
        NSRunningApplication.runningApplications(withBundleIdentifier: MdvCommand.appBundleIdentifier)
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
