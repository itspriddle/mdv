import Foundation
import Testing

@testable import PeepApp

/// The Homebrew cask's link (#84): Install Command Line Tool… sees it as Homebrew's and neither
/// installs beside it nor removes it.
@MainActor
@Suite("Install Command Line Tool: Homebrew cask")
struct CommandLineToolHomebrewTests {
    let sandbox: CommandLineToolSandbox
    let app: URL
    let user: CommandLineToolLocation
    /// An Apple silicon prefix, which the menu doesn't offer.
    let appleSilicon: HomebrewCask
    /// An Intel prefix, whose `bin` is the menu's `/usr/local/bin`.
    let intel: HomebrewCask

    init() throws {
        sandbox = try CommandLineToolSandbox()
        app = try sandbox.makeApp("Peep.app")
        user = CommandLineToolLocation(folder: sandbox.bin, displayPath: "~/.local/bin")
        appleSilicon = HomebrewCask(prefix: sandbox.root.appending(path: "opt/homebrew", directoryHint: .isDirectory))
        intel = HomebrewCask(prefix: sandbox.root.appending(path: "usr/local", directoryHint: .isDirectory))
    }

    func controller(_ casks: [HomebrewCask]) -> CommandLineToolController {
        CommandLineToolController(
            locations: [user, intel.location], homebrew: casks,
            makeInstaller: { [sandbox, app] in sandbox.installer(app: app, folder: $0.folder) },
            privileged: RecordingRunner())
    }

    /// What `brew install --cask peep` leaves: the Caskroom folder and `bin/peep` into the app.
    func installCask(_ cask: HomebrewCask, linkingTo destination: String? = nil) throws {
        let caskroom = cask.prefix.appending(path: "Caskroom/peep/0.1.0", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: caskroom, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cask.location.folder, withIntermediateDirectories: true)
        let helper = app.appending(path: "Contents/Helpers/peep").path(percentEncoded: false)
        try FileManager.default.createSymbolicLink(
            atPath: cask.location.folder.appending(path: "peep").path(percentEncoded: false),
            withDestinationPath: destination ?? helper)
    }

    @Test("the cask's link on Apple silicon is Homebrew's: the item says so instead of installing")
    func appleSiliconCask() throws {
        defer { sandbox.remove() }
        #expect(controller([appleSilicon]).currentAction() == .install(preferred: nil))
        try installCask(appleSilicon)
        let action = controller([appleSilicon]).currentAction()
        #expect(action == .homebrew(appleSilicon.location))
        #expect(action.menuTitle == "Command Line Tool Installed by Homebrew…")
    }

    @Test("on Intel the cask's link in /usr/local/bin isn't offered for uninstall")
    func intelCask() throws {
        defer { sandbox.remove() }
        try installCask(intel)
        #expect(controller([intel]).currentAction() == .homebrew(intel.location))
    }

    @Test("the same link without the Caskroom folder is the installer's own, to uninstall")
    func ownLinkInUsrLocal() throws {
        defer { sandbox.remove() }
        try installCask(intel)
        try FileManager.default.removeItem(at: intel.prefix.appending(path: "Caskroom"))
        #expect(!intel.isInstalled)
        #expect(controller([intel]).currentAction() == .uninstall(intel.location))
    }

    @Test("a link of this copy's own elsewhere can still be uninstalled beside the cask")
    func ownLinkBesideCask() async throws {
        defer { sandbox.remove() }
        try installCask(appleSilicon)
        try await sandbox.installer(app: app).install()
        #expect(controller([appleSilicon]).currentAction() == .uninstall(user))
    }

    @Test("the cask's link to a moved app is still Homebrew's; a foreign one isn't")
    func movedAndForeign() throws {
        defer { sandbox.remove() }
        try installCask(appleSilicon, linkingTo: "/Gone/Peep.app/Contents/Helpers/peep")
        #expect(controller([appleSilicon]).currentAction() == .homebrew(appleSilicon.location))

        try installCask(intel, linkingTo: "/usr/bin/true")
        #expect(controller([intel]).currentAction() == .install(preferred: nil))
    }

    @Test("tests never look at the real Homebrew prefixes")
    func standard() {
        defer { sandbox.remove() }
        #expect(HomebrewCask.standard.isEmpty)
    }
}
