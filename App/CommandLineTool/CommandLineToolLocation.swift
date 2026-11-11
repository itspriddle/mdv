import Darwin
import Foundation

/// A folder the command line tool can be installed in (#70).
struct CommandLineToolLocation: Equatable, Sendable {
    let folder: URL
    /// The folder as the reader knows it (`~/.local/bin`).
    let displayPath: String
    /// Where the man page's link goes (#71): `<folder>/../share/man/man1` by default, which
    /// `man` searches for every `bin` folder on the `PATH` (no `MANPATH` needed).
    let manFolder: URL

    init(folder: URL, displayPath: String, manFolder: URL? = nil) {
        self.folder = folder
        self.displayPath = displayPath
        self.manFolder =
            manFolder
            ?? folder.deletingLastPathComponent().appending(path: "share/man/man1", directoryHint: .isDirectory)
    }

    /// `~/.local/bin`: no password, but not always on the reader's `PATH`.
    static var userBin: CommandLineToolLocation {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return CommandLineToolLocation(
            folder: home.appending(path: ".local/bin", directoryHint: .isDirectory), displayPath: "~/.local/bin")
    }

    /// `/usr/local/bin`: on every `PATH`, but usually needs an administrator's password.
    static let usrLocalBin = CommandLineToolLocation(
        folder: URL(filePath: "/usr/local/bin", directoryHint: .isDirectory), displayPath: "/usr/local/bin")

    /// The locations the menu offers: both standard folders, or only the folder a UI test
    /// passed (`-MdvUITestCommandLineToolFolder`; its man page goes inside it, never beside
    /// it). None under hosted unit tests or a UI test without that hook, so tests never touch
    /// the real folders.
    @MainActor static var standard: [CommandLineToolLocation] {
        if let folder = UITestHooks.commandLineToolFolder {
            return [
                CommandLineToolLocation(
                    folder: folder, displayPath: folder.path(percentEncoded: false),
                    manFolder: folder.appending(path: "share/man/man1", directoryHint: .isDirectory))
            ]
        }
        let isTesting = AppDelegate.isHostingUnitTests
        if isTesting || UITestHooks.isUITesting {
            return []
        }
        return [userBin, usrLocalBin]
    }

    /// Whether changing the folder needs an administrator: it (or, if missing, the nearest
    /// folder above it that exists) isn't writable by the reader.
    var needsAdministrator: Bool {
        var url = folder
        while true {
            let path = url.path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: path) {
                return access(path, W_OK) != 0
            }
            let parent = url.deletingLastPathComponent()
            if parent == url {
                return true
            }
            url = parent
        }
    }

    /// The line that puts this folder on a shell's `PATH`.
    var pathLine: String {
        let folder = displayPath.hasPrefix("~/") ? "$HOME/" + displayPath.dropFirst(2) : displayPath
        return "export PATH=\"\(folder):$PATH\""
    }

    /// Whether `pathFolders` (from `LoginShellPath`) includes this folder.
    func isOnPath(_ pathFolders: [String]) -> Bool {
        let mine = folder.standardized.path(percentEncoded: false)
        return pathFolders.contains {
            URL(filePath: $0, directoryHint: .isDirectory).standardized.path(percentEncoded: false) == mine
        }
    }
}

/// The reader's `PATH` as their login shell sets it: a GUI app's own environment has only the
/// system default. Runs `<shell> -l -c 'printf %s "$PATH"'` (the reader's own shell and
/// profile, nothing from mdv or a document) with no input and a time limit. Interactive-only
/// files such as `~/.zshrc` aren't read, so a folder added there can look missing; the install
/// alert then shows the line to add, worded as a check.
enum LoginShellPath {
    /// The folders on the login shell's `PATH`, or nil when it couldn't be read in `timeout`.
    static func folders(timeout: TimeInterval = 2) async -> [String]? {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                once.resume(with: read(timeout: timeout))
            }
            // A profile that starts a background job holding stdout open must not hang the menu.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout + 0.5) {
                once.resume(with: nil)
            }
        }
    }

    private static func read(timeout: TimeInterval) -> [String]? {
        let process = Process()
        process.executableURL = loginShell()
        process.arguments = ["-l", "-c", "printf '%s' \"$PATH\""]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        do {
            try process.run()
        } catch {
            return nil
        }
        let timer = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0,
            let path = String(bytes: data, encoding: .utf8)
        else {
            return nil
        }
        return path.split(separator: ":").map(String.init)
    }

    /// The reader's login shell from the user database, else zsh.
    private static func loginShell() -> URL {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if path.hasPrefix("/"), access(path, X_OK) == 0 {
                return URL(filePath: path)
            }
        }
        return URL(filePath: "/bin/zsh")
    }

    /// Resumes a continuation once, from whichever of the read and the deadline comes first.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<[String]?, Never>?

        init(_ continuation: CheckedContinuation<[String]?, Never>) {
            self.continuation = continuation
        }

        func resume(with value: [String]?) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: value)
        }
    }
}
