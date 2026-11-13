import Foundation

/// Which updater this launch gets (#81). Tests and development builds never reach the network.
///
/// | Launch | Updater |
/// | --- | --- |
/// | Hosted unit tests, UI tests (`-PeepUITesting`) | `InactiveUpdater` |
/// | Cold-open measurement (`PEEP_LAUNCH_TIMING`) | `InactiveUpdater` (no permission prompt mid-run) |
/// | Debug | `InactiveUpdater`, unless `-PeepUpdateFeedURL <url>` is given |
/// | Release | `SparkleUpdater` with Info.plist's feed |
///
/// Testing updates by hand (the issue's manual check): build an older Debug copy (lower
/// `CURRENT_PROJECT_VERSION`) and a newer one signed with the same identity, archive the newer
/// one into a folder, run Sparkle's `generate_appcast` on it (it signs the archive and, as
/// `SURequireSignedFeed` needs, the feed; the private key must be in the login keychain), serve
/// the folder (`python3 -m http.server 8000 --bind 127.0.0.1`), then launch the older copy with
/// `-PeepUpdateFeedURL http://127.0.0.1:8000/appcast.xml` and choose Check for Updates…. The
/// public key in `Config/Shared.xcconfig` must match. Sparkle's tools are in
/// `build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin`.
enum SoftwareUpdates {
    enum Mode: Equatable {
        /// No updater: `InactiveUpdater`.
        case off
        /// Sparkle, with Info.plist's feed or (Debug only) this one.
        case sparkle(feedURLOverride: URL?)
    }

    #if DEBUG
        /// Launch argument (a `UserDefaults` key) that turns the updater on in a Debug build,
        /// pointed at this feed (an `http` or `https` URL). Ignored under tests.
        static let feedURLKey = "PeepUpdateFeedURL"
    #endif

    /// The updater for this launch.
    @MainActor
    static func makeUpdater() -> any SoftwareUpdating {
        let mode = mode(
            isHostingUnitTests: AppDelegate.isHostingUnitTests, isUITesting: UITestHooks.isUITesting,
            isMeasuringLaunch: LaunchTiming.isEnabled, isDebug: isDebugBuild, debugFeedURL: debugFeedURL)
        switch mode {
        case .off:
            return InactiveUpdater()
        case .sparkle(let feedURLOverride):
            return SparkleUpdater(feedURLOverride: feedURLOverride)
        }
    }

    /// The rule, apart from the process, so tests can check every row of the table.
    static func mode(
        isHostingUnitTests: Bool, isUITesting: Bool, isMeasuringLaunch: Bool, isDebug: Bool, debugFeedURL: URL?
    ) -> Mode {
        if isHostingUnitTests || isUITesting || isMeasuringLaunch {
            return .off
        }
        guard isDebug else {
            return .sparkle(feedURLOverride: nil)
        }
        guard let debugFeedURL, let scheme = debugFeedURL.scheme?.lowercased(), ["http", "https"].contains(scheme)
        else {
            return .off
        }
        return .sparkle(feedURLOverride: debugFeedURL)
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    /// `-PeepUpdateFeedURL`'s value. Always nil in Release.
    private static var debugFeedURL: URL? {
        #if DEBUG
            UserDefaults.standard.string(forKey: feedURLKey).flatMap { URL(string: $0) }
        #else
            nil
        #endif
    }
}
