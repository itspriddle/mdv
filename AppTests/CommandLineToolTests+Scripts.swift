import Foundation
import Testing

@testable import MdvApp

@Suite("Install Command Line Tool: privileged scripts")
struct CommandLineToolScriptTests {
    let sandbox: CommandLineToolSandbox
    let app: URL

    init() throws {
        sandbox = try CommandLineToolSandbox()
        app = try sandbox.makeApp("mdv.app")
    }

    func runInstall(target: URL, expected: String = "") async throws(PrivilegedRunError) {
        try await ShellRunner().run(
            script: CommandLineToolInstaller.privilegedInstallScript,
            arguments: [target.path(percentEncoded: false), sandbox.link.path(percentEncoded: false), expected])
    }

    var target: URL { app.appending(path: "Contents/Helpers/mdv") }

    @Test("install script: links a fresh path, creating the folder, and leaves no temporary link")
    func fresh() async throws {
        defer { sandbox.remove() }
        try FileManager.default.removeItem(at: sandbox.bin)
        try await runInstall(target: target)
        #expect(try sandbox.destination() == target.path(percentEncoded: false))
        #expect(try sandbox.binContents() == ["mdv"])
    }

    @Test("install script: replaces our link only when it has the expected destination")
    func replace() async throws {
        defer { sandbox.remove() }
        try sandbox.makeLink(to: "/Old/mdv.app/Contents/Helpers/mdv")
        await #expect(throws: PrivilegedRunError.self) { try await runInstall(target: target) }
        await #expect(throws: PrivilegedRunError.self) {
            try await runInstall(target: target, expected: "/Elsewhere/mdv.app/Contents/Helpers/mdv")
        }
        #expect(try sandbox.destination() == "/Old/mdv.app/Contents/Helpers/mdv")
        try await runInstall(target: target, expected: "/Old/mdv.app/Contents/Helpers/mdv")
        #expect(try sandbox.destination() == target.path(percentEncoded: false))
        #expect(try sandbox.binContents() == ["mdv"])
    }

    @Test("install script: refuses a file, and a link to a folder, with status 3")
    func refuses() async throws {
        defer { sandbox.remove() }
        try Data("x".utf8).write(to: sandbox.link)
        let error = await #expect(throws: PrivilegedRunError.self) { try await runInstall(target: target) }
        #expect(error == .exitStatus(3, message: ""))
        #expect(try String(contentsOf: sandbox.link, encoding: .utf8) == "x")

        try FileManager.default.removeItem(at: sandbox.link)
        let folder = sandbox.root.appending(path: "Folder/mdv.app/Contents/Helpers/mdv", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try sandbox.makeLink(to: folder.path(percentEncoded: false))
        await #expect(throws: PrivilegedRunError.self) {
            try await runInstall(target: target, expected: folder.path(percentEncoded: false))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).isEmpty)
    }

    @Test("install script: paths with quotes, spaces, and shell syntax are only ever arguments")
    func hostilePaths() async throws {
        defer { sandbox.remove() }
        let marker = sandbox.root.appending(path: "pwned")
        let name = "it's \"mdv\" $(touch \(marker.path(percentEncoded: false))) `id`;.app"
        let hostile = try sandbox.makeApp(name)
        let target = hostile.appending(path: "Contents/Helpers/mdv")
        try await runInstall(target: target)
        #expect(try sandbox.destination() == target.path(percentEncoded: false))
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }

    @Test("the AppleScript runner passes hostile paths as quoted words and reports exit statuses")
    func appleScriptRunner() async throws {
        defer { sandbox.remove() }
        // The app's runner without `with administrator privileges` (no password prompt).
        let runner = AppleScriptPrivilegedRunner(asAdministrator: false)
        #expect(AppleScriptPrivilegedRunner.source.contains("with administrator privileges"))
        #expect(!AppleScriptPrivilegedRunner.unprivilegedSource.contains("administrator"))
        let marker = sandbox.root.appending(path: "pwned")
        let name = "it's \"mdv\" $(touch \(marker.path(percentEncoded: false))) `id`; \\ \n.app"
        let hostile = try sandbox.makeApp(name)
        let target = hostile.appending(path: "Contents/Helpers/mdv").path(percentEncoded: false)
        try await runner.run(
            script: CommandLineToolInstaller.privilegedInstallScript,
            arguments: [target, sandbox.link.path(percentEncoded: false), ""])
        #expect(try sandbox.destination() == target)
        #expect(sandbox.installer(app: hostile).state() == .installed)
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))

        let error = await #expect(throws: PrivilegedRunError.self) {
            try await runner.run(
                script: CommandLineToolInstaller.privilegedUninstallScript,
                arguments: [sandbox.link.path(percentEncoded: false), "/somewhere/else"])
        }
        #expect(error.map { if case .exitStatus(3, _) = $0 { true } else { false } } == true)
        #expect(try sandbox.destination() == target)
    }

    @Test("uninstall script: removes only a link with the expected destination")
    func uninstall() async throws {
        defer { sandbox.remove() }
        let script = CommandLineToolInstaller.privilegedUninstallScript
        let link = sandbox.link.path(percentEncoded: false)
        try sandbox.makeLink(to: "/bin/ls")
        await #expect(throws: PrivilegedRunError.self) {
            try await ShellRunner().run(script: script, arguments: [link, target.path(percentEncoded: false)])
        }
        #expect(try sandbox.destination() == "/bin/ls")
        try await ShellRunner().run(script: script, arguments: [link, "/bin/ls"])
        #expect(try sandbox.binContents().isEmpty)

        try Data().write(to: sandbox.link)
        await #expect(throws: PrivilegedRunError.self) {
            try await ShellRunner().run(script: script, arguments: [link, ""])
        }
        #expect(FileManager.default.fileExists(atPath: link))
    }
}

@MainActor
@Suite("Install Command Line Tool: menu")
struct CommandLineToolControllerTests {
    let sandbox: CommandLineToolSandbox
    let app: URL
    let user: CommandLineToolLocation
    let system: CommandLineToolLocation

    init() throws {
        sandbox = try CommandLineToolSandbox()
        app = try sandbox.makeApp("mdv.app")
        user = CommandLineToolLocation(folder: sandbox.bin, displayPath: "~/.local/bin")
        system = CommandLineToolLocation(
            folder: sandbox.root.appending(path: "usr-local-bin", directoryHint: .isDirectory),
            displayPath: "/usr/local/bin")
        try FileManager.default.createDirectory(at: system.folder, withIntermediateDirectories: true)
    }

    func controller() -> CommandLineToolController {
        CommandLineToolController(
            locations: [user, system],
            makeInstaller: { [sandbox, app] in sandbox.installer(app: app, folder: $0.folder) },
            privileged: RecordingRunner())
    }

    @Test("the item installs, repairs a moved app's link, or uninstalls this copy's")
    func actions() async throws {
        defer { sandbox.remove() }
        let controller = controller()
        #expect(controller.currentAction() == .install(preferred: nil))
        #expect(controller.currentAction().menuTitle == "Install Command Line Tool…")

        let systemLink = system.folder.appending(path: "mdv").path(percentEncoded: false)
        try FileManager.default.createSymbolicLink(
            atPath: systemLink, withDestinationPath: "/Gone/mdv.app/Contents/Helpers/mdv")
        #expect(controller.currentAction() == .repair(system))
        #expect(controller.currentAction().menuTitle == "Repair Command Line Tool…")

        try await sandbox.installer(app: app).install()
        #expect(controller.currentAction() == .uninstall(user))
        #expect(controller.currentAction().menuTitle == "Uninstall Command Line Tool…")
    }

    @Test("a link to another copy preselects its location; a foreign file isn't ours anywhere")
    func otherCopyAndForeign() throws {
        defer { sandbox.remove() }
        try Data().write(to: sandbox.link)
        let copy = try sandbox.makeApp("mdv copy.app")
        try FileManager.default.createSymbolicLink(
            atPath: system.folder.appending(path: "mdv").path(percentEncoded: false),
            withDestinationPath: copy.appending(path: "Contents/Helpers/mdv").path(percentEncoded: false))
        #expect(controller().currentAction() == .install(preferred: system))
    }

    @Test("without locations (tests without the hook) the item is unavailable")
    func unavailable() {
        defer { sandbox.remove() }
        #expect(!CommandLineToolController(locations: []).isAvailable)
        #expect(CommandLineToolLocation.standard.isEmpty)
    }

    @Test("PATH help: the line to add, and whether a folder is on PATH")
    func pathHelp() {
        defer { sandbox.remove() }
        #expect(CommandLineToolLocation.userBin.pathLine == "export PATH=\"$HOME/.local/bin:$PATH\"")
        #expect(CommandLineToolLocation.usrLocalBin.pathLine == "export PATH=\"/usr/local/bin:$PATH\"")
        #expect(CommandLineToolLocation.usrLocalBin.isOnPath(["/usr/bin", "/usr/local/bin/"]))
        #expect(!CommandLineToolLocation.usrLocalBin.isOnPath(["/usr/bin"]))
        #expect(!user.needsAdministrator)
        #expect(
            CommandLineToolLocation(folder: URL(filePath: "/System/mdv-test/bin"), displayPath: "").needsAdministrator)
    }

    @Test("the menu shows the item in the App menu after Settings")
    func menu() throws {
        defer { sandbox.remove() }
        let menu = MainMenu.build()
        let appMenu = try #require(menu.items.first?.submenu)
        let titles = appMenu.items.map { $0.isSeparatorItem ? "-" : $0.title }
        let settings = try #require(titles.firstIndex(of: "Settings…"))
        #expect(titles[settings + 1] == "-")
        #expect(titles[settings + 2] == "Install Command Line Tool…")
    }
}
