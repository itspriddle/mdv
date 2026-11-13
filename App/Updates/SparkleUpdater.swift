import Foundation
import Sparkle

/// The real updater (#81): Sparkle 2's `SPUStandardUpdaterController` (its standard alerts and
/// update window), created without starting, then started at launch by `AppDelegate` through
/// `start()`. A misconfigured build (say, the placeholder public key) logs the error and Sparkle
/// shows an alert after a few seconds.
///
/// The feed, public key, and security options are in Info.plist (`project.yml`): HTTPS
/// `https://peep.now/appcast.xml`, `SUPublicEDKey`, `SUVerifyUpdateBeforeExtraction`, and
/// `SURequireSignedFeed`. One default channel: `allowedChannels(for:)` is empty, so items tagged
/// with a `sparkle:channel` (a future beta) are skipped until a setting opts in.
@MainActor
final class SparkleUpdater: NSObject, SoftwareUpdating, SPUUpdaterDelegate {
    /// A Debug-only feed in place of Info.plist's (`SoftwareUpdates.Mode.sparkle`), for testing
    /// against a local appcast. Always nil in Release.
    private let feedURLOverride: URL?
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    init(feedURLOverride: URL?) {
        self.feedURLOverride = feedURLOverride
        super.init()
    }

    private var updater: SPUUpdater { controller.updater }

    let isActive = true

    var canCheckForUpdates: Bool { updater.canCheckForUpdates }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }

    var allowsAutomaticUpdates: Bool { updater.allowsAutomaticUpdates }

    func start() {
        controller.startUpdater()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? {
        feedURLOverride?.absoluteString
    }

    /// Only the default channel. A beta channel is an item with `<sparkle:channel>beta</…>` in
    /// the same appcast plus "beta" here when the reader opts in (VISION; no setting yet).
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        []
    }
}
