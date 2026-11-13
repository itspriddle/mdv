import Foundation

/// What the app needs from its updater (#81): App menu > Check for Updates… and the two
/// Settings > General rows. `SparkleUpdater` is the real one; `InactiveUpdater` stands in
/// wherever updates are off (`SoftwareUpdates.mode`), and tests use fakes. No implementation
/// keeps its own copy of the settings: Sparkle's updater owns them (in Peep's defaults, under
/// its own `SU…` keys).
@MainActor
protocol SoftwareUpdating: AnyObject {
    /// Whether this updater ever reaches the network. False for `InactiveUpdater`.
    var isActive: Bool { get }
    /// Whether Check for Updates… can run now (false while a check or update is in progress).
    var canCheckForUpdates: Bool { get }
    /// Whether the updater checks once a day on its own.
    var automaticallyChecksForUpdates: Bool { get set }
    /// Whether updates found by those checks download and install without asking.
    var automaticallyDownloadsUpdates: Bool { get set }
    /// Whether `automaticallyDownloadsUpdates` can be changed (it needs automatic checks).
    var allowsAutomaticUpdates: Bool { get }

    /// Starts the updater, once, at launch (`AppDelegate`).
    func start()
    /// Checks now, showing the result (App menu > Check for Updates…).
    func checkForUpdates()
}

/// The updater for builds and launches that never check (Debug, hosted unit tests, UI tests,
/// cold-open measurements). It never touches the network; its settings live in memory only, so
/// Settings' rows still work (and UI tests can toggle them) without changing the reader's.
@MainActor
final class InactiveUpdater: SoftwareUpdating {
    let isActive = false
    let canCheckForUpdates = false
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    var allowsAutomaticUpdates: Bool { automaticallyChecksForUpdates }

    func start() {}
    func checkForUpdates() {}
}
