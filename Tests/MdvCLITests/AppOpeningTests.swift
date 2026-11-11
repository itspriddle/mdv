import Foundation
import Testing

@testable import MdvCLIKit

@Suite("Opening in the app")
struct AppOpeningTests {
    @Test("FILEs without an output flag go to the app as absolute URLs, in order")
    func files() async throws {
        let folder = try TempFolder()
        try folder.file("a.md", "# A")
        let opener = RecordingAppOpener()
        // Relative paths resolve against the working directory (the package root under swift test).
        let result = await CLIHarness.run(["Package.swift", folder.path("a.md")], appOpener: opener)
        #expect(result.status == 0)
        #expect(result.stdout.isEmpty)
        let cwd = FileManager.default.currentDirectoryPath
        #expect(
            result.openedInApp == [
                AppOpenRequest(files: [
                    URL(fileURLWithPath: "\(cwd)/Package.swift"), URL(fileURLWithPath: folder.path("a.md")),
                ])
            ])
    }

    @Test("standard input goes to the app as text")
    func standardInput() async {
        let result = await CLIHarness.run([], stdin: Data("# Piped\n".utf8))
        #expect(result.status == 0)
        #expect(result.openedInApp == [AppOpenRequest(files: [], standardInput: "# Piped\n")])
    }

    @Test("standard input that isn't UTF-8 never reaches the app")
    func invalidStandardInput() async {
        let result = await CLIHarness.run([], stdin: Data([0xFF]))
        #expect(result.status == 65)
        #expect(result.openedInApp.isEmpty)
    }

    @Test("an opener failure is reported with its status")
    func failure() async throws {
        let folder = try TempFolder()
        try folder.file("a.md", "# A")
        let opener = RecordingAppOpener(
            failingWith: CLIError("couldn't open the app", status: ExitStatus.unavailable))
        let result = await CLIHarness.run([folder.path("a.md")], appOpener: opener)
        #expect(result.status == 69)
        #expect(result.stderr == "mdv: couldn't open the app\n")
    }

    // MARK: Path checks

    @Test("a missing file, a folder, or an unreadable file opens nothing, even with good files")
    func badPaths() async throws {
        let folder = try TempFolder()
        let good = try folder.file("good.md", "# Good")
        let unreadable = try folder.file("secret.md", "# Secret")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable) }
        let cases = [
            (folder.path("missing.md"), "No such file or directory"),
            (folder.url.path, "Is a directory"),
            (unreadable, "Permission denied"),
        ]
        for (path, reason) in cases {
            let result = await CLIHarness.run([good, path])
            #expect(result.status == 66, "\(path)")
            #expect(result.stderr == "mdv: \(path): \(reason)\n")
            #expect(result.openedInApp.isEmpty)
        }
    }

    // MARK: - -theme and --flavor

    @Test("--theme goes to the app as the resolved id", arguments: [("serif", "serif"), ("Document", "document")])
    func theme(flag: String, id: String) async throws {
        let folder = try TempFolder()
        let file = try folder.file("a.md", "# A")
        let result = await CLIHarness.run(["--theme", flag, file])
        #expect(result.status == 0)
        #expect(result.openedInApp.map(\.themeID) == [id])
    }

    @Test("a custom --theme from the Themes folder goes to the app")
    func customTheme() async throws {
        let folder = try TempFolder()
        let file = try folder.file("a.md", "# A")
        let themes = try TempFolder()
        try themes.file("plain.css", "/* mdv-theme\nname: Plain\n*/\nbody { color: black; }\n")
        let result = await CLIHarness.run(["--theme", "custom:plain.css", file], themesFolder: themes.url)
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.openedInApp.map(\.themeID) == ["custom:plain.css"])
    }

    @Test("an unknown or missing --theme opens nothing", arguments: [("nope", 64), ("custom:missing.css", 66)])
    func badTheme(id: String, status: Int32) async throws {
        let folder = try TempFolder()
        let file = try folder.file("a.md", "# A")
        let themes = try TempFolder()
        let result = await CLIHarness.run(["--theme", id, file], themesFolder: themes.url)
        #expect(result.status == status)
        #expect(result.openedInApp.isEmpty)
    }

    @Test("--flavor without HTML output is a usage error")
    func flavorWithoutHTML() async throws {
        let folder = try TempFolder()
        let file = try folder.file("a.md", "# A")
        let result = await CLIHarness.run(["--flavor", "commonmark", file])
        #expect(result.status == 64)
        #expect(result.stderr.contains("--flavor is for --html"))
        #expect(result.openedInApp.isEmpty)
    }

    // MARK: Finding the app

    @Test("the CLI inside an app bundle opens that app; elsewhere, the app found by bundle id")
    func locator() throws {
        let folder = try TempFolder()
        let app = folder.url.appending(path: "Dev Build/mdv.app", directoryHint: .isDirectory)
        try Self.makeApp(at: app, bundleIdentifier: MdvCommand.appBundleIdentifier)
        let helper = app.appending(path: "Contents/Helpers/mdv").path(percentEncoded: false)
        #expect(AppLocator.containingApp(ofExecutableAt: helper)?.standardizedFileURL == app.standardizedFileURL)

        let installed = URL(filePath: "/Applications/mdv.app", directoryHint: .isDirectory)
        let inside = AppLocator(executablePath: { helper }, applicationForBundleIdentifier: { _ in installed })
        #expect(try inside.locate().standardizedFileURL == app.standardizedFileURL)

        let swiftRun = AppLocator(
            executablePath: { "/tmp/.build/debug/mdv" }, applicationForBundleIdentifier: { _ in installed })
        #expect(try swiftRun.locate() == installed)

        let nowhere = AppLocator(executablePath: { nil }, applicationForBundleIdentifier: { _ in nil })
        #expect(throws: CLIError.self) { try nowhere.locate() }
    }

    @Test("an app bundle with another bundle id, or a helper elsewhere in it, isn't mdv's")
    func locatorRejects() throws {
        let folder = try TempFolder()
        let other = folder.url.appending(path: "Other.app", directoryHint: .isDirectory)
        try Self.makeApp(at: other, bundleIdentifier: "com.example.other")
        #expect(AppLocator.containingApp(ofExecutableAt: other.appending(path: "Contents/Helpers/mdv").path) == nil)
        let app = folder.url.appending(path: "mdv.app", directoryHint: .isDirectory)
        try Self.makeApp(at: app, bundleIdentifier: MdvCommand.appBundleIdentifier)
        #expect(AppLocator.containingApp(ofExecutableAt: app.appending(path: "Contents/MacOS/mdv").path) == nil)
    }

    @Test("Launch Services is bypassed only when another copy with the same bundle id runs")
    func target() {
        let ours = URL(filePath: "/build/Debug/mdv.app", directoryHint: .isDirectory)
        let installed = URL(filePath: "/Applications/mdv.app", directoryHint: .isDirectory)
        #expect(AppLocator.target(for: ours, running: []) == .launchServices(createsNewInstance: false))
        #expect(AppLocator.target(for: ours, running: [(10, ours)]) == .launchServices(createsNewInstance: false))
        #expect(AppLocator.target(for: ours, running: [(11, installed)]) == .launchServices(createsNewInstance: true))
        #expect(AppLocator.target(for: ours, running: [(11, installed), (10, ours)]) == .running(10))
        // A running app's bundle URL ends in a slash; the located app's may not.
        let bare = URL(filePath: "/build/Debug/mdv.app", directoryHint: .notDirectory)
        #expect(AppLocator.target(for: bare, running: [(11, installed), (10, ours)]) == .running(10))
        #expect(AppLocator.isSameBundle(bare, ours))
        #expect(!AppLocator.isSameBundle(bare, installed))
    }

    static func makeApp(at app: URL, bundleIdentifier: String) throws {
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: contents.appending(path: "Helpers"), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier, "CFBundlePackageType": "APPL", "CFBundleExecutable": "mdv",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        try Data().write(to: contents.appending(path: "Helpers/mdv"))
    }
}
