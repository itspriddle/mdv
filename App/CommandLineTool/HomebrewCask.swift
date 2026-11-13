import Foundation

/// A Homebrew prefix where the Peep cask (#84) may have linked the command: its `binary` stanza
/// makes `<prefix>/bin/peep`, a link into the installed Peep.app (and `manpage` links
/// `<prefix>/share/man/man1/peep.1`). Homebrew owns those links, so Install Command Line Tool…
/// neither offers to install beside them nor removes them (`CommandLineToolController`).
struct HomebrewCask: Equatable, Sendable {
    /// The cask's token, its folder name in the Caskroom.
    static let token = "peep"

    /// `/opt/homebrew` (Apple silicon) or `/usr/local` (Intel).
    let prefix: URL

    /// Where the cask links the command, as a location the installer can read.
    var location: CommandLineToolLocation {
        let bin = prefix.appending(path: "bin", directoryHint: .isDirectory)
        return CommandLineToolLocation(folder: bin, displayPath: bin.path(percentEncoded: false))
    }

    /// Whether Homebrew has the cask installed: `<prefix>/Caskroom/peep` is a folder.
    var isInstalled: Bool {
        let caskroom = prefix.appending(path: "Caskroom/\(Self.token)", directoryHint: .isDirectory)
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: caskroom.path(percentEncoded: false), isDirectory: &isFolder)
            && isFolder.boolValue
    }

    /// The default prefixes on Apple silicon and Intel. None under tests (like
    /// `CommandLineToolLocation.standard`), so a developer's own cask install never changes them.
    @MainActor static var standard: [HomebrewCask] {
        if AppDelegate.isHostingUnitTests || UITestHooks.isUITesting {
            return []
        }
        return ["/opt/homebrew", "/usr/local"].map {
            HomebrewCask(prefix: URL(filePath: $0, directoryHint: .isDirectory))
        }
    }
}
