import Foundation
import Testing

@testable import PeepApp

/// The man page and completions that go with the command (#71): the man page is a second
/// `CommandLineToolInstaller.Item`, installed and removed in the same batch as the command.
@Suite("Install Command Line Tool: man page")
struct CommandLineToolManPageTests {
    let sandbox: CommandLineToolSandbox
    let app: URL
    let command: CommandLineToolInstaller
    let manPage: CommandLineToolInstaller

    init() throws {
        sandbox = try CommandLineToolSandbox()
        app = try sandbox.makeApp("Peep.app")
        command = sandbox.installer(app: app)
        manPage = sandbox.manPageInstaller(app: app)
    }

    private func path(_ url: URL) -> String { url.path(percentEncoded: false) }

    @Test("the man page links into share/man/man1 beside the bin folder")
    func location() {
        defer { sandbox.remove() }
        let location = CommandLineToolLocation(folder: sandbox.bin, displayPath: "~/.local/bin")
        #expect(location.manFolder.standardized.pathComponents == sandbox.manFolder.standardized.pathComponents)
        #expect(
            CommandLineToolLocation.usrLocalBin.manFolder.pathComponents == [
                "/", "usr", "local", "share", "man", "man1",
            ])
        #expect(manPage.target == app.appending(path: "Contents/Resources/man/man1/peep.1"))
    }

    @Test("a batch installs the command and the man page, and uninstalls both")
    func batch() async throws {
        defer { sandbox.remove() }
        try await CommandLineToolInstaller.install([command, manPage])
        #expect(command.state() == .installed)
        #expect(manPage.state() == .installed)
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: path(sandbox.manLink)) == path(manPage.target))
        try await CommandLineToolInstaller.uninstall([command, manPage])
        #expect(command.state() == .notInstalled)
        #expect(manPage.state() == .notInstalled)
    }

    @Test("anything in the way of one item stops the whole batch before it changes anything")
    func occupiedStopsBatch() async throws {
        defer { sandbox.remove() }
        try FileManager.default.createDirectory(at: sandbox.manFolder, withIntermediateDirectories: true)
        try Data("someone else's page".utf8).write(to: sandbox.manLink)
        await #expect(throws: CommandLineToolError.occupied(.file)) {
            try await CommandLineToolInstaller.install([command, manPage])
        }
        #expect(command.state() == .notInstalled)
        #expect(try String(contentsOf: sandbox.manLink, encoding: .utf8) == "someone else's page")
    }

    @Test("folders that need an administrator share one privileged run")
    func onePrivilegedRun() async throws {
        defer { sandbox.remove() }
        try FileManager.default.createDirectory(at: sandbox.manFolder, withIntermediateDirectories: true)
        for folder in [sandbox.bin, sandbox.manFolder] {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path(folder))
        }
        let runner = RecordingRunner()
        try await CommandLineToolInstaller.install([command, manPage], privileged: runner)
        #expect(runner.runs.count == 1)
        #expect(
            runner.runs.first?.arguments == [
                path(command.target), path(sandbox.link), "", path(manPage.target), path(sandbox.manLink), "",
            ])
    }

    @Test("a writable folder is changed directly; only the other goes to the privileged run")
    func mixedFolders() async throws {
        defer { sandbox.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path(sandbox.bin))
        let runner = RecordingRunner()
        try await CommandLineToolInstaller.install([command, manPage], privileged: runner)
        #expect(manPage.state() == .installed)
        #expect(runner.runs.first?.arguments == [path(command.target), path(sandbox.link), ""])
    }

    @Test("the scripts take several links, and check them all before changing any")
    func batchScripts() async throws {
        defer { sandbox.remove() }
        let install = CommandLineToolInstaller.privilegedInstallScript
        let arguments = [path(command.target), path(sandbox.link), "", path(manPage.target), path(sandbox.manLink), ""]
        try await ShellRunner().run(script: install, arguments: arguments)
        #expect(command.state() == .installed)
        #expect(manPage.state() == .installed)

        // Uninstall refuses both when one link isn't what it should be.
        let uninstall = CommandLineToolInstaller.privilegedUninstallScript
        await #expect(throws: PrivilegedRunError.self) {
            try await ShellRunner().run(
                script: uninstall, arguments: [path(sandbox.link), path(command.target), path(sandbox.manLink), "/x"])
        }
        #expect(command.state() == .installed)
        try await ShellRunner().run(
            script: uninstall,
            arguments: [path(sandbox.link), path(command.target), path(sandbox.manLink), path(manPage.target)])
        #expect(command.state() == .notInstalled)
        #expect(manPage.state() == .notInstalled)

        // Install refuses both when the second path holds a file.
        try Data().write(to: sandbox.manLink)
        let error = await #expect(throws: PrivilegedRunError.self) {
            try await ShellRunner().run(script: install, arguments: arguments)
        }
        #expect(error == .exitStatus(3, message: ""))
        #expect(command.state() == .notInstalled)
    }

    @MainActor
    @Test("the menu installs the man page only when this copy has one and the path is free or ours")
    func manPageToInstall() throws {
        defer { sandbox.remove() }
        let location = CommandLineToolLocation(folder: sandbox.bin, displayPath: "~/.local/bin")
        let withPage = CommandLineToolController(
            locations: [location], makeInstaller: { [sandbox, app] in sandbox.installer(app: app, folder: $0.folder) },
            makeManPageInstaller: { [sandbox, app] in sandbox.manPageInstaller(app: app, folder: $0.manFolder) },
            privileged: RecordingRunner())
        #expect(withPage.manPageToInstall(at: location)?.linkURL.path(percentEncoded: false) == path(sandbox.manLink))

        let bare = try sandbox.makeApp("Bare.app")
        try FileManager.default.removeItem(at: bare.appending(path: "Contents/Resources"))
        let withoutPage = CommandLineToolController(
            locations: [location], makeInstaller: { [sandbox] in sandbox.installer(app: bare, folder: $0.folder) },
            makeManPageInstaller: { [sandbox] in sandbox.manPageInstaller(app: bare, folder: $0.manFolder) },
            privileged: RecordingRunner())
        #expect(withoutPage.manPageToInstall(at: location) == nil)

        try FileManager.default.createDirectory(at: sandbox.manFolder, withIntermediateDirectories: true)
        try Data().write(to: sandbox.manLink)
        #expect(withPage.manPageToInstall(at: location) == nil)
    }

    @Test("the app bundles completion scripts for zsh, bash, and fish")
    func bundledCompletions() {
        defer { sandbox.remove() }
        let folder = Bundle.main.bundleURL.appending(path: CommandLineToolController.completionsPathInBundle)
        for name in ["_peep", "peep.bash", "peep.fish"] {
            let script = try? String(contentsOf: folder.appending(path: name), encoding: .utf8)
            #expect(script?.contains("peep") == true, "\(name) is missing from the bundle")
        }
    }
}
