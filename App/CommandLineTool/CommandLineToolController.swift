import AppKit

/// App menu > Install / Repair / Uninstall Command Line Tool… (#70): works out what the item
/// does from what is in each location, and runs it with alerts. The rules are
/// `CommandLineToolInstaller`'s.
@MainActor
final class CommandLineToolController {
    /// What the menu item does now.
    enum Action: Equatable {
        /// Nothing of ours anywhere, or a link to another copy (`location` is that link's).
        case install(preferred: CommandLineToolLocation?)
        /// A link to a moved or renamed app: offer to point it at this copy.
        case repair(CommandLineToolLocation)
        /// A link to this copy.
        case uninstall(CommandLineToolLocation)
        /// The Homebrew cask's link (#84): Homebrew installs and removes it, so the item only
        /// says so.
        case homebrew(CommandLineToolLocation)

        var menuTitle: String {
            switch self {
            case .install: "Install Command Line Tool…"
            case .repair: "Repair Command Line Tool…"
            case .uninstall: "Uninstall Command Line Tool…"
            case .homebrew: "Command Line Tool Installed by Homebrew…"
            }
        }
    }

    let locations: [CommandLineToolLocation]
    /// Where the Homebrew cask may have linked the command (#84).
    let homebrew: [HomebrewCask]
    private let makeInstaller: (CommandLineToolLocation) -> CommandLineToolInstaller
    private let makeManPageInstaller: (CommandLineToolLocation) -> CommandLineToolInstaller
    private let privileged: any PrivilegedRunning
    private var isRunning = false

    init(
        locations: [CommandLineToolLocation] = CommandLineToolLocation.standard,
        homebrew: [HomebrewCask] = HomebrewCask.standard,
        makeInstaller: @escaping (CommandLineToolLocation) -> CommandLineToolInstaller = {
            CommandLineToolInstaller(folder: $0.folder)
        },
        makeManPageInstaller: @escaping (CommandLineToolLocation) -> CommandLineToolInstaller = {
            CommandLineToolInstaller(folder: $0.manFolder, item: .manPage)
        },
        privileged: any PrivilegedRunning = AppleScriptPrivilegedRunner()
    ) {
        self.locations = locations
        self.homebrew = homebrew
        self.makeInstaller = makeInstaller
        self.makeManPageInstaller = makeManPageInstaller
        self.privileged = privileged
    }

    /// Whether the menu item is shown (false under tests without the folder hook).
    var isAvailable: Bool {
        !locations.isEmpty
    }

    /// What the item does, read fresh from disk (a few `lstat`s) each time the menu opens.
    /// This is also how a link left dangling by a moved app is detected: the item becomes
    /// Repair; nothing is fixed without asking.
    ///
    /// A Homebrew cask's link (#84) is Homebrew's: its folder is left out of the others (on Intel
    /// it is `/usr/local/bin`), and unless this copy has its own link elsewhere to uninstall, the
    /// item only says Homebrew installed it, so nothing installs a second `peep` beside it.
    func currentAction() -> Action {
        let cask = homebrewLocation()
        let states = locations.filter { $0.folder.standardized != cask?.folder.standardized }.map {
            ($0, makeInstaller($0).state())
        }
        if let installed = states.first(where: { $0.1 == .installed }) {
            return .uninstall(installed.0)
        }
        if let cask {
            return .homebrew(cask)
        }
        if let dangling = states.first(where: { if case .dangling = $0.1 { true } else { false } }) {
            return .repair(dangling.0)
        }
        let otherCopy = states.first { if case .otherCopy = $0.1 { true } else { false } }
        return .install(preferred: otherCopy?.0)
    }

    /// The menu item's action.
    func run() async {
        guard isAvailable, !isRunning else {
            return
        }
        isRunning = true
        defer { isRunning = false }
        switch currentAction() {
        case .uninstall(let location):
            await uninstall(from: location)
        case .repair(let location):
            await install(preferred: location, isRepair: true)
        case .install(let preferred):
            await install(preferred: preferred, isRepair: false)
        case .homebrew(let location):
            showHomebrew(at: location)
        }
    }

    // MARK: - Homebrew

    /// The folder of the Homebrew cask's link, if the cask is installed and the link is ours
    /// (to any copy of Peep, or to one that was moved: `brew reinstall` fixes that).
    func homebrewLocation() -> CommandLineToolLocation? {
        homebrew.lazy.filter(\.isInstalled).map(\.location).first {
            let state = makeInstaller($0).state()
            return state == .installed || state.ourDestination != nil
        }
    }

    private func showHomebrew(at location: CommandLineToolLocation) {
        let alert = NSAlert()
        alert.messageText = "Homebrew installed the Peep command line tool."
        alert.informativeText =
            "\(location.displayPath)/peep comes with Peep’s Homebrew cask, along with `man peep` and shell "
            + "completions. Homebrew keeps them up to date and removes them with `brew uninstall --cask peep`, "
            + "so Peep leaves them alone."
        alert.runModal()
    }

    // MARK: - Install

    private func install(preferred: CommandLineToolLocation?, isRepair: Bool) async {
        // Which locations are on the reader's PATH, to pick the default and to say whether a
        // line needs adding. Only worth a shell when there is a choice.
        let pathFolders = locations.count > 1 ? await LoginShellPath.folders() : nil
        let noPassword = locations.first { !$0.needsAdministrator && $0.isOnPath(pathFolders ?? []) }
        guard let initial = preferred ?? noPassword ?? locations.last,
            let location = askToInstall(selecting: initial, isRepair: isRepair)
        else {
            return
        }
        let installer = makeInstaller(location)
        if case .occupied(let occupant) = installer.state() {
            showOccupied(occupant, at: location, installer: installer)
            return
        }
        let manPage = manPageToInstall(at: location)
        do {
            try await CommandLineToolInstaller.install(
                [installer] + [manPage].compactMap(\.self), privileged: privileged)
        } catch .cancelled {
            return
        } catch .occupied(let occupant) {
            showOccupied(occupant, at: location, installer: installer)
            return
        } catch {
            showFailure("Peep couldn’t install the command line tool.", error)
            return
        }
        showInstalled(at: location, withManPage: manPage != nil, onPath: pathFolders.map(location.isOnPath))
    }

    /// The man page's installer when it goes along with the command (#71): this copy has one
    /// (a build without `make cli-docs` doesn't), and nothing that isn't ours is in its place.
    /// A man page from elsewhere (say, a package manager's) is left alone, without an alert:
    /// the command is what the reader asked for.
    func manPageToInstall(at location: CommandLineToolLocation) -> CommandLineToolInstaller? {
        let installer = makeManPageInstaller(location)
        guard FileManager.default.fileExists(atPath: installer.target.path(percentEncoded: false)) else {
            return nil
        }
        if case .occupied = installer.state() {
            return nil
        }
        return installer
    }

    /// Asks where to install, saying which copy of Peep the link will use. Returns nil on Cancel.
    private func askToInstall(selecting initial: CommandLineToolLocation, isRepair: Bool) -> CommandLineToolLocation? {
        let alert = NSAlert()
        let thisApp = Bundle.main.bundleURL
        if isRepair, case .dangling(let destination) = makeInstaller(initial).state() {
            alert.messageText = "Repair the Peep command line tool?"
            alert.informativeText =
                "\(initial.displayPath)/peep points to \(destination), which is gone (Peep was moved or "
                + "renamed). Repairing points it to this copy of peep:\n\n\(thisApp.path(percentEncoded: false))"
            alert.addButton(withTitle: "Repair")
        } else {
            alert.messageText = "Install the Peep command line tool?"
            var text =
                "This adds a link named peep that runs the command line tool in this copy of Peep:\n\n"
                + thisApp.path(percentEncoded: false)
            if case .otherCopy(let app, _) = makeInstaller(initial).state() {
                let copy = app.path(percentEncoded: false)
                text += "\n\nThe link in \(initial.displayPath) now points to the copy at \(copy)."
            } else if !Self.otherCopies().isEmpty {
                text += "\n\nThere are other copies of Peep on this Mac; the link uses this one."
            }
            alert.informativeText = text
            alert.addButton(withTitle: "Install")
        }
        alert.addButton(withTitle: "Cancel")

        let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26), pullsDown: false)
        popUp.setAccessibilityIdentifier("command-line-tool-location")
        for location in locations {
            let note = location.needsAdministrator ? " (needs an administrator password)" : ""
            popUp.addItem(withTitle: location.displayPath + note)
        }
        popUp.selectItem(at: locations.firstIndex(of: initial) ?? 0)
        if !isRepair, locations.count > 1 {
            alert.accessoryView = popUp
        }

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        return isRepair ? initial : locations[max(popUp.indexOfSelectedItem, 0)]
    }

    private func showInstalled(at location: CommandLineToolLocation, withManPage: Bool, onPath: Bool?) {
        let alert = NSAlert()
        alert.messageText = "The Peep command line tool is installed."
        var text = "\(location.displayPath)/peep runs the command line tool in this copy of Peep. Try `peep --help`"
        text += withManPage ? " or `man peep`." : "."
        let completions = Bundle.main.bundleURL.appending(path: Self.completionsPathInBundle).path(
            percentEncoded: false)
        text +=
            "\n\nShell completions for zsh, bash, and fish are in \(completions) "
            + "(Peep’s README explains how to use them)."
        if onPath != true {
            text +=
                "\n\n\(location.displayPath) may not be on your PATH. If `peep` isn’t found in a new terminal "
                + "window, add this line to your shell’s startup file (~/.zshrc for zsh):\n\n\(location.pathLine)"
        }
        alert.informativeText = text
        alert.runModal()
    }

    /// Shows what is in the way and stops: install never replaces it.
    private func showOccupied(
        _ occupant: CommandLineToolInstaller.Occupant, at location: CommandLineToolLocation,
        installer: CommandLineToolInstaller
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Peep didn’t install the command line tool."
        var text =
            "\(installer.linkURL.path(percentEncoded: false)) is already there: \(Self.describe(occupant)). "
            + "Peep only replaces or removes its own link, so it left this alone. Move or delete it and try again"
        text += locations.count > 1 ? ", or choose the other location." : "."
        alert.informativeText = text
        alert.runModal()
    }

    // MARK: - Uninstall

    private func uninstall(from location: CommandLineToolLocation) async {
        let installer = makeInstaller(location)
        let alert = NSAlert()
        alert.messageText = "Uninstall the Peep command line tool?"
        alert.informativeText =
            "This removes the link \(installer.linkURL.path(percentEncoded: false)). Peep itself stays where it is."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        do {
            // The man page goes with the command when it is ours (any copy's); anything else stays.
            let manPage = makeManPageInstaller(location)
            let ours = manPage.state() == .installed || manPage.state().ourDestination != nil
            try await CommandLineToolInstaller.uninstall(
                ours ? [installer, manPage] : [installer], privileged: privileged)
        } catch .cancelled {
            return
        } catch {
            showFailure("Peep couldn’t uninstall the command line tool.", error)
        }
    }

    // MARK: - Helpers

    /// Where the build puts the shell completion scripts (project.yml, #71).
    nonisolated static let completionsPathInBundle = "Contents/Resources/completions"

    private func showFailure(_ message: String, _ error: CommandLineToolError) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    /// How an alert names what is in the way.
    static func describe(_ occupant: CommandLineToolInstaller.Occupant) -> String {
        switch occupant {
        case .file: "a file"
        case .folder: "a folder"
        case .link(let destination): "a link to \(destination)"
        case .other: "something that isn’t a file or a link"
        }
    }

    /// Other copies of Peep Launch Services knows about (dev builds, a copy in Downloads).
    private static func otherCopies() -> [URL] {
        guard let identifier = Bundle.main.bundleIdentifier else {
            return []
        }
        let thisApp = Bundle.main.bundleURL.standardized
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: identifier).filter {
            $0.standardized != thisApp
        }
    }
}
