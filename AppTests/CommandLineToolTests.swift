import Foundation
import Testing

@testable import MdvApp

@Suite("Install Command Line Tool")
struct CommandLineToolInstallerTests {
    let sandbox: CommandLineToolSandbox
    let app: URL
    let installer: CommandLineToolInstaller

    init() throws {
        sandbox = try CommandLineToolSandbox()
        app = try sandbox.makeApp("mdv.app")
        installer = sandbox.installer(app: app)
    }

    var target: String { installer.target.path(percentEncoded: false) }

    @Test("a fresh install links mdv to this copy's helper, atomically, leaving nothing else")
    func freshInstall() async throws {
        defer { sandbox.remove() }
        #expect(installer.state() == .notInstalled)
        try await installer.install()
        #expect(installer.state() == .installed)
        #expect(try sandbox.destination() == target)
        #expect(try sandbox.binContents() == ["mdv"])
    }

    @Test("a fresh install creates a missing folder")
    func createsFolder() async throws {
        defer { sandbox.remove() }
        let folder = sandbox.root.appending(path: "home/.local/bin", directoryHint: .isDirectory)
        let installer = sandbox.installer(app: app, folder: folder)
        try await installer.install()
        #expect(installer.state() == .installed)
    }

    @Test("installing when already installed changes nothing")
    func alreadyInstalled() async throws {
        defer { sandbox.remove() }
        try await installer.install()
        let before = try FileManager.default.attributesOfItem(atPath: sandbox.link.path(percentEncoded: false))
        try await installer.install()
        let after = try FileManager.default.attributesOfItem(atPath: sandbox.link.path(percentEncoded: false))
        #expect(installer.state() == .installed)
        #expect(before[.systemFileNumber] as? Int == after[.systemFileNumber] as? Int)
    }

    @Test("a file in the way is shown and left alone, by install and uninstall")
    func foreignFile() async throws {
        defer { sandbox.remove() }
        try Data("someone else's mdv".utf8).write(to: sandbox.link)
        #expect(installer.state() == .occupied(.file))
        await #expect(throws: CommandLineToolError.occupied(.file)) { try await installer.install() }
        await #expect(throws: CommandLineToolError.occupied(.file)) { try await installer.uninstall() }
        #expect(try String(contentsOf: sandbox.link, encoding: .utf8) == "someone else's mdv")
        #expect(try sandbox.binContents() == ["mdv"])
    }

    @Test("a folder in the way is left alone")
    func foreignFolder() async throws {
        defer { sandbox.remove() }
        try FileManager.default.createDirectory(at: sandbox.link, withIntermediateDirectories: false)
        await #expect(throws: CommandLineToolError.occupied(.folder)) { try await installer.install() }
        await #expect(throws: CommandLineToolError.occupied(.folder)) { try await installer.uninstall() }
    }

    @Test("a link to another program is shown and left alone")
    func foreignSymlink() async throws {
        defer { sandbox.remove() }
        try sandbox.makeLink(to: "/usr/bin/true")
        let occupied = CommandLineToolInstaller.State.occupied(.link(destination: "/usr/bin/true"))
        #expect(installer.state() == occupied)
        await #expect(throws: CommandLineToolError.occupied(.link(destination: "/usr/bin/true"))) {
            try await installer.install()
        }
        #expect(try sandbox.destination() == "/usr/bin/true")
    }

    @Test("a link into another app with the same layout isn't ours")
    func linkIntoOtherApp() async throws {
        defer { sandbox.remove() }
        let other = try sandbox.makeApp("Other.app", bundleIdentifier: "com.example.other")
        let destination = other.appending(path: "Contents/Helpers/mdv").path(percentEncoded: false)
        try sandbox.makeLink(to: destination)
        #expect(installer.state() == .occupied(.link(destination: destination)))
        await #expect(throws: CommandLineToolError.occupied(.link(destination: destination))) {
            try await installer.install()
        }
        await #expect(throws: CommandLineToolError.occupied(.link(destination: destination))) {
            try await installer.uninstall()
        }
        #expect(try sandbox.destination() == destination)
    }

    @Test("a relative link isn't ours")
    func relativeLink() async throws {
        defer { sandbox.remove() }
        try sandbox.makeLink(to: "../Apps/mdv.app/Contents/Helpers/mdv")
        #expect(installer.state() == .occupied(.link(destination: "../Apps/mdv.app/Contents/Helpers/mdv")))
    }

    @Test("a link to a moved app is dangling, and install repairs it")
    func danglingRepaired() async throws {
        defer { sandbox.remove() }
        let gone = sandbox.root.appending(path: "Old/mdv.app/Contents/Helpers/mdv").path(percentEncoded: false)
        try sandbox.makeLink(to: gone)
        #expect(installer.state() == .dangling(destination: gone))
        try await installer.install()
        #expect(installer.state() == .installed)
        #expect(try sandbox.binContents() == ["mdv"])
    }

    @Test("a dangling link of ours can be uninstalled")
    func danglingUninstalled() async throws {
        defer { sandbox.remove() }
        try sandbox.makeLink(to: sandbox.root.appending(path: "Old/mdv 2.app/Contents/Helpers/mdv").path())
        try await installer.uninstall()
        #expect(installer.state() == .notInstalled)
    }

    @Test("a link to another copy says which, and install points it at this one")
    func otherCopy() async throws {
        defer { sandbox.remove() }
        let copy = try sandbox.makeApp("mdv copy.app")
        let destination = copy.appending(path: "Contents/Helpers/mdv").path(percentEncoded: false)
        try sandbox.makeLink(to: destination)
        guard case .otherCopy(let linked, destination) = installer.state() else {
            Issue.record("not otherCopy: \(installer.state())")
            return
        }
        #expect(linked.path(percentEncoded: false) == copy.path(percentEncoded: false))
        try await installer.install()
        #expect(try sandbox.destination() == target)
    }

    @Test("uninstall removes our link, and only the link")
    func uninstall() async throws {
        defer { sandbox.remove() }
        try await installer.install()
        try await installer.uninstall()
        #expect(installer.state() == .notInstalled)
        #expect(FileManager.default.fileExists(atPath: target))
        await #expect(throws: CommandLineToolError.notInstalled) { try await installer.uninstall() }
    }

    @Test("uninstall of a foreign link is refused")
    func uninstallForeignLink() async throws {
        defer { sandbox.remove() }
        try sandbox.makeLink(to: "/bin/ls")
        await #expect(throws: CommandLineToolError.occupied(.link(destination: "/bin/ls"))) {
            try await installer.uninstall()
        }
        #expect(try sandbox.destination() == "/bin/ls")
    }

    @Test("a folder the reader can't write needs an administrator, and goes to the privileged runner")
    func readOnlyFolder() async throws {
        defer { sandbox.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sandbox.bin.path())
        await #expect(throws: CommandLineToolError.needsAdministrator) { try await installer.install() }
        let runner = RecordingRunner()
        try await installer.install(privileged: runner)
        #expect(runner.runs.count == 1)
        #expect(runner.runs.first?.script == CommandLineToolInstaller.privilegedInstallScript)
        #expect(runner.runs.first?.arguments == [target, sandbox.link.path(percentEncoded: false), ""])

        runner.result = .cancelled
        await #expect(throws: CommandLineToolError.cancelled) { try await installer.install(privileged: runner) }
        runner.result = .exitStatus(1, message: "mv: nope")
        await #expect(throws: CommandLineToolError.failed("mv: nope")) {
            try await installer.install(privileged: runner)
        }
    }

    @Test("a privileged install doesn't run for something in the way")
    func privilegedRefusesForeign() async throws {
        defer { sandbox.remove() }
        try Data().write(to: sandbox.link)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sandbox.bin.path())
        let runner = RecordingRunner()
        await #expect(throws: CommandLineToolError.occupied(.file)) { try await installer.install(privileged: runner) }
        await #expect(throws: CommandLineToolError.occupied(.file)) {
            try await installer.uninstall(privileged: runner)
        }
        #expect(runner.runs.isEmpty)
    }

    @Test("a privileged uninstall passes the link and the destination it must have")
    func privilegedUninstall() async throws {
        defer { sandbox.remove() }
        try await installer.install()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sandbox.bin.path())
        await #expect(throws: CommandLineToolError.needsAdministrator) { try await installer.uninstall() }
        let runner = RecordingRunner()
        try await installer.uninstall(privileged: runner)
        #expect(runner.runs.first?.script == CommandLineToolInstaller.privilegedUninstallScript)
        #expect(runner.runs.first?.arguments == [sandbox.link.path(percentEncoded: false), target])
    }
}
