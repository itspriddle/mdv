import Darwin
import Foundation

/// Installs and removes the `mdv` command (#70): a symbolic link at `<folder>/mdv` to the CLI
/// inside an mdv.app (`Contents/Helpers/mdv`).
///
/// The folder and the app are injected, so tests run over temp folders and fake app bundles.
/// The rules:
/// - **Ours** is a symbolic link whose absolute destination is `<X>.app/Contents/Helpers/mdv`,
///   where `X.app` is gone (the app moved: `dangling`) or is an app with our bundle identifier.
///   Anything else at the path (a file, a folder, a link elsewhere or into another app) is
///   `occupied`: install shows it and stops, uninstall refuses.
/// - Links are created atomically: a temporary link in the same folder is renamed onto the path
///   (`RENAME_EXCL` when nothing is there, so a file that appears meanwhile is never replaced).
///   A replace or removal first checks that the link still has the destination it was read with.
/// - A folder the reader can't write (`/usr/local/bin`) throws `needsAdministrator` unless a
///   `PrivilegedRunning` is given; then the fixed `privilegedInstallScript` /
///   `privilegedUninstallScript` run with the paths as arguments (VISION's security model).
///
/// Each installed file is one `Item` (`item` defaults to the command), with an installer over
/// its own folder. `install(_:privileged:)` and `uninstall(_:privileged:)` change several
/// together (the command and its man page, #71) with at most one privileged run.
struct CommandLineToolInstaller: Sendable {
    /// One file the installer links into a folder.
    struct Item: Equatable, Sendable {
        /// The link's name in the folder.
        let name: String
        /// The link's destination, relative to the app bundle.
        let pathInBundle: String

        /// The `mdv` command.
        static let command = Item(name: "mdv", pathInBundle: "Contents/Helpers/mdv")

        /// The man page (#71), linked into `CommandLineToolLocation.manFolder`, where `man mdv`
        /// finds it for a command on the `PATH`. The build copies it into the bundle
        /// (project.yml, from `make cli-docs`).
        static let manPage = Item(name: "mdv.1", pathInBundle: "Contents/Resources/man/man1/mdv.1")
    }

    /// What isn't ours at the link's path.
    enum Occupant: Equatable, Sendable {
        case file
        case folder
        /// A symbolic link that doesn't point into an mdv.app.
        case link(destination: String)
        /// Something else (a socket, a device, or a path that couldn't be read).
        case other
    }

    /// What is at the link's path.
    enum State: Equatable, Sendable {
        /// Nothing (the folder may not exist yet).
        case notInstalled
        /// Our link, to this copy of mdv.
        case installed
        /// Our link, to another copy of mdv that still exists.
        case otherCopy(app: URL, destination: String)
        /// Our link, to an mdv.app that was moved, renamed, or deleted.
        case dangling(destination: String)
        /// Not ours: never replaced or removed.
        case occupied(Occupant)

        /// The destination of our link, for a state that has one (not `installed`).
        var ourDestination: String? {
            switch self {
            case .otherCopy(_, let destination), .dangling(let destination):
                destination
            case .notInstalled, .installed, .occupied:
                nil
            }
        }
    }

    let folder: URL
    let item: Item
    /// This copy of mdv.
    let app: URL
    /// The bundle identifier an existing app must have for a link into it to count as ours.
    let bundleIdentifier: String

    init(
        folder: URL, item: Item = .command, app: URL = Bundle.main.bundleURL,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? ""
    ) {
        self.folder = folder
        self.item = item
        self.app = app
        self.bundleIdentifier = bundleIdentifier
    }

    /// The link's path, `<folder>/mdv`.
    var linkURL: URL {
        folder.appending(path: item.name, directoryHint: .notDirectory)
    }

    /// The file the link points to in this copy of mdv.
    var target: URL {
        app.appending(path: item.pathInBundle, directoryHint: .notDirectory)
    }

    private var linkPath: String { linkURL.path(percentEncoded: false) }
    private var targetPath: String { target.path(percentEncoded: false) }

    // MARK: - State

    /// What is at the link's path now.
    func state() -> State {
        var info = stat()
        guard lstat(linkPath, &info) == 0 else {
            return errno == ENOENT ? .notInstalled : .occupied(.other)
        }
        switch info.st_mode & S_IFMT {
        case S_IFLNK:
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath) else {
                return .occupied(.other)
            }
            return state(ofLinkTo: destination)
        case S_IFREG:
            return .occupied(.file)
        case S_IFDIR:
            return .occupied(.folder)
        default:
            return .occupied(.other)
        }
    }

    private func state(ofLinkTo destination: String) -> State {
        guard let linkedApp = appBundle(containing: destination) else {
            return .occupied(.link(destination: destination))
        }
        if Self.samePath(destination, targetPath) {
            return .installed
        }
        let appPath = linkedApp.path(percentEncoded: false)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: appPath, isDirectory: &isFolder) else {
            return .dangling(destination: destination)
        }
        // An app is there: it is ours only if it says so.
        guard isFolder.boolValue, Self.bundleIdentifier(of: linkedApp) == bundleIdentifier else {
            return .occupied(.link(destination: destination))
        }
        return FileManager.default.fileExists(atPath: destination)
            ? .otherCopy(app: linkedApp, destination: destination) : .dangling(destination: destination)
    }

    /// The `.app` a link destination of the form `<X>.app/<item.pathInBundle>` points into.
    private func appBundle(containing destination: String) -> URL? {
        guard destination.hasPrefix("/") else {
            return nil
        }
        let path = URL(filePath: destination).standardized.path(percentEncoded: false)
        let suffix = "/" + item.pathInBundle
        guard path.hasSuffix(suffix) else {
            return nil
        }
        let appPath = String(path.dropLast(suffix.count))
        guard appPath.hasSuffix(".app"), let name = appPath.split(separator: "/").last, name.count > ".app".count
        else {
            return nil
        }
        return URL(filePath: appPath, directoryHint: .isDirectory)
    }

    private static func bundleIdentifier(of app: URL) -> String? {
        let plist = app.appending(path: "Contents/Info.plist", directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: plist),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }
        return info["CFBundleIdentifier"] as? String
    }

    private static func samePath(_ lhs: String, _ rhs: String) -> Bool {
        let left = URL(filePath: lhs).standardized
        let right = URL(filePath: rhs).standardized
        return left == right || left.resolvingSymlinksInPath() == right.resolvingSymlinksInPath()
    }
}

// MARK: - Install and uninstall

extension CommandLineToolInstaller {
    /// Links `<folder>/mdv` to this copy, creating the folder if needed. Does nothing when it is
    /// already installed; replaces our link to another copy or a moved app; throws `occupied`
    /// for anything else. With `privileged`, a folder the reader can't write is handled by the
    /// privileged script (an administrator password prompt); without it, that throws
    /// `needsAdministrator`.
    func install(privileged: (any PrivilegedRunning)? = nil) async throws(CommandLineToolError) {
        try await Self.install([self], privileged: privileged)
    }

    /// Installs several items together (#71: the command and its man page). Nothing changes when
    /// any of them is `occupied`. Each link whose folder the reader can write is made directly;
    /// the rest go to one privileged run, so the reader sees one password prompt.
    static func install(
        _ installers: [Self], privileged: (any PrivilegedRunning)? = nil
    ) async throws(CommandLineToolError) {
        let states = installers.map { $0.state() }
        for case .occupied(let occupant) in states {
            throw .occupied(occupant)
        }
        var pending: [String] = []
        for (installer, current) in zip(installers, states) where current != .installed {
            do throws(CommandLineToolError) {
                try installer.createFolder()
                try installer.link(replacing: current.ourDestination)
            } catch .needsAdministrator {
                pending += [installer.targetPath, installer.linkPath, current.ourDestination ?? ""]
            }
        }
        guard !pending.isEmpty else {
            return
        }
        guard let privileged else {
            throw .needsAdministrator
        }
        try await runPrivileged(
            privileged, script: privilegedInstallScript, arguments: pending, installers: installers)
    }

    /// Removes our link (to any copy of mdv, or a moved one). Throws `notInstalled` when nothing
    /// is there and `occupied` for anything that isn't ours.
    func uninstall(privileged: (any PrivilegedRunning)? = nil) async throws(CommandLineToolError) {
        if state() == .notInstalled {
            throw .notInstalled
        }
        try await Self.uninstall([self], privileged: privileged)
    }

    /// Removes our links among `installers`, skipping those with nothing installed; nothing
    /// changes when any of them is `occupied`. Like `install(_:privileged:)`, the links the
    /// reader can't remove go to one privileged run.
    static func uninstall(
        _ installers: [Self], privileged: (any PrivilegedRunning)? = nil
    ) async throws(CommandLineToolError) {
        var removals: [(installer: Self, destination: String)] = []
        for installer in installers {
            switch installer.state() {
            case .notInstalled:
                continue
            case .occupied(let occupant):
                throw .occupied(occupant)
            case .installed:
                let link = installer.linkPath
                let destination =
                    (try? FileManager.default.destinationOfSymbolicLink(atPath: link)) ?? installer.targetPath
                removals.append((installer, destination))
            case .otherCopy(_, let linked), .dangling(let linked):
                removals.append((installer, linked))
            }
        }
        var pending: [String] = []
        for (installer, destination) in removals {
            do throws(CommandLineToolError) {
                guard installer.currentDestination() == destination else {
                    throw CommandLineToolError.changed
                }
                guard unlink(installer.linkPath) == 0 else {
                    throw CommandLineToolError(errno: errno)
                }
            } catch .needsAdministrator {
                pending += [installer.linkPath, destination]
            }
        }
        guard !pending.isEmpty else {
            return
        }
        guard let privileged else {
            throw .needsAdministrator
        }
        try await runPrivileged(
            privileged, script: privilegedUninstallScript, arguments: pending, installers: installers)
    }

    private func createFolder() throws(CommandLineToolError) {
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isFolder) {
            guard isFolder.boolValue else {
                throw .failed("\(folder.path(percentEncoded: false)) isn’t a folder.")
            }
            return
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            throw .needsAdministrator
        } catch {
            throw .failed(error.localizedDescription)
        }
    }

    /// Creates a temporary link beside the path and renames it into place: exclusively when
    /// `expected` is nil, else over our link if it still points to `expected`.
    private func link(replacing expected: String?) throws(CommandLineToolError) {
        let temporary = folder.appending(path: ".\(item.name)-install-\(UUID().uuidString)").path(percentEncoded: false)
        guard symlink(targetPath, temporary) == 0 else {
            throw CommandLineToolError(errno: errno)
        }
        let result: Int32
        if let expected {
            guard currentDestination() == expected else {
                unlink(temporary)
                throw .changed
            }
            result = rename(temporary, linkPath)
        } else {
            result = renamex_np(temporary, linkPath, UInt32(RENAME_EXCL))
        }
        guard result == 0 else {
            let code = errno
            unlink(temporary)
            throw code == EEXIST ? .changed : CommandLineToolError(errno: code)
        }
    }

    /// The destination of the symbolic link at the path, or nil if it isn't one.
    private func currentDestination() -> String? {
        var info = stat()
        guard lstat(linkPath, &info) == 0, info.st_mode & S_IFMT == S_IFLNK else {
            return nil
        }
        return try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)
    }

    private static func runPrivileged(
        _ runner: any PrivilegedRunning, script: String, arguments: [String], installers: [Self]
    ) async throws(CommandLineToolError) {
        // The paths are arguments, never part of the script; they still must be absolute
        // (so none reads as an option) and free of NUL, which a C string can't carry.
        for argument in arguments where !argument.isEmpty {
            guard argument.hasPrefix("/"), !argument.contains("\0") else {
                throw .failed("Unexpected path: \(argument)")
            }
        }
        do throws(PrivilegedRunError) {
            try await runner.run(script: script, arguments: arguments)
        } catch {
            switch error {
            case .cancelled:
                throw .cancelled
            case .exitStatus(Self.refusedStatus, _):
                // The script found something else at a path (it changed since `state()`).
                for installer in installers {
                    if case .occupied(let occupant) = installer.state() {
                        throw .occupied(occupant)
                    }
                }
                throw .changed
            case .exitStatus(_, let message), .failed(let message):
                throw .failed(message)
            }
        }
    }
}
