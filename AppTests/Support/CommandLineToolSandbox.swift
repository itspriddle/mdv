import Foundation
import Testing

@testable import PeepApp

/// Runs the installer's privileged scripts the way `AppleScriptPrivilegedRunner` does
/// (`/bin/sh -c <script> peep <arguments>…`), without privileges, over temp folders.
struct ShellRunner: PrivilegedRunning {
    func run(script: String, arguments: [String]) async throws(PrivilegedRunError) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script, "peep"] + arguments
        let errors = Pipe()
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw .failed(error.localizedDescription)
        }
        let message = String(bytes: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw .exitStatus(process.terminationStatus, message: message)
        }
    }
}

/// Records privileged runs and answers with `result`.
final class RecordingRunner: PrivilegedRunning, @unchecked Sendable {
    private(set) var runs: [(script: String, arguments: [String])] = []
    var result: PrivilegedRunError?

    func run(script: String, arguments: [String]) async throws(PrivilegedRunError) {
        runs.append((script, arguments))
        if let result {
            throw result
        }
    }
}

/// A temp folder with fake Peep.app bundles and a `bin` folder to install into.
struct CommandLineToolSandbox {
    static let bundleIdentifier = "now.peep.Peep"
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "peep-cli-install-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    }

    var bin: URL { root.appending(path: "bin", directoryHint: .isDirectory) }
    var link: URL { bin.appending(path: "peep") }

    /// A fake app bundle with an Info.plist and a `Contents/Helpers/peep` file.
    @discardableResult
    func makeApp(_ name: String, bundleIdentifier: String = bundleIdentifier) throws -> URL {
        let app = root.appending(path: "Apps/\(name)", directoryHint: .isDirectory)
        let helpers = app.appending(path: "Contents/Helpers", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let info = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": bundleIdentifier], format: .xml, options: 0)
        try info.write(to: app.appending(path: "Contents/Info.plist"))
        try Data("#!/bin/sh\n".utf8).write(to: helpers.appending(path: "peep"))
        let man = app.appending(path: "Contents/Resources/man/man1", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: man, withIntermediateDirectories: true)
        try Data(".Dd x\n".utf8).write(to: man.appending(path: "peep.1"))
        return app
    }

    /// Where the man page's link goes for `bin` (`share/man/man1` beside it).
    var manFolder: URL { root.appending(path: "share/man/man1", directoryHint: .isDirectory) }
    var manLink: URL { manFolder.appending(path: "peep.1") }

    func manPageInstaller(app: URL, folder: URL? = nil) -> CommandLineToolInstaller {
        CommandLineToolInstaller(
            folder: folder ?? manFolder, item: .manPage, app: app, bundleIdentifier: Self.bundleIdentifier)
    }

    func installer(app: URL, folder: URL? = nil) -> CommandLineToolInstaller {
        CommandLineToolInstaller(folder: folder ?? bin, app: app, bundleIdentifier: Self.bundleIdentifier)
    }

    func destination() throws -> String {
        try FileManager.default.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))
    }

    func makeLink(to destination: String) throws {
        try FileManager.default.createSymbolicLink(
            atPath: link.path(percentEncoded: false), withDestinationPath: destination)
    }

    /// Everything in `bin`, to check no temporary links are left behind.
    func binContents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: bin.path(percentEncoded: false)).sorted()
    }

    func remove() {
        for folder in [bin, manFolder] {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
        }
        try? FileManager.default.removeItem(at: root)
    }
}
