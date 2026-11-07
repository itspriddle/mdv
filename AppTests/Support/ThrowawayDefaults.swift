import Foundation
import Testing

/// A `UserDefaults` suite for one test, removed when this object goes away.
///
/// A named suite (`UserDefaults(suiteName: "x")`) leaves `~/Library/Preferences/x.plist` behind
/// even after `removePersistentDomain(forName:)` and `removeSuite(named:)`: cfprefsd writes the
/// emptied domain back, and deleting that file races with its write. So the suite is named by
/// an absolute path inside its own temporary folder (CFPreferences stores such a domain at that
/// path), and cleanup removes the domain, the suite, and the folder. Nothing reaches the
/// reader's preferences, and `defaults domains` doesn't grow.
final class ThrowawayDefaults {
    let defaults: UserDefaults
    /// The suite name: an absolute path, `<folder>/defaults`.
    let suiteName: String
    private let folder: URL

    init(_ label: String = "mdv-tests") throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "\(label)-defaults-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        suiteName = folder.appending(path: "defaults").path(percentEncoded: false)
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        defaults.removeSuite(named: suiteName)
        try? FileManager.default.removeItem(at: folder)
    }
}
