import AppKit
import Foundation
import Testing

@testable import PeepApp

/// Sparkle updates (#81): which launches get an updater, App menu > Check for Updates…, and
/// Settings > General's rows, all over a fake updater. Nothing here starts Sparkle or reaches
/// the network.
@MainActor
@Suite("Updates")
struct UpdatesTests {
    let throwaway: ThrowawayDefaults

    init() throws {
        throwaway = try ThrowawayDefaults("peep-updates-tests")
    }

    /// Records what the app asks of it; settings follow Sparkle's rule that automatic downloads
    /// need automatic checks.
    final class FakeUpdater: SoftwareUpdating {
        var isActive = true
        var canCheckForUpdates = true
        var automaticallyChecksForUpdates = false
        var automaticallyDownloadsUpdates = false
        var allowsAutomaticUpdates: Bool { automaticallyChecksForUpdates }
        private(set) var starts = 0
        private(set) var checks = 0

        func start() {
            starts += 1
        }

        func checkForUpdates() {
            checks += 1
        }
    }

    // MARK: Which updater

    @Test("tests and cold-open measurements never get an updater, in any build")
    func offUnderTests() {
        let feed = URL(string: "http://127.0.0.1:8000/appcast.xml")
        for isDebug in [false, true] {
            for (hosting, uiTesting, measuring) in [(true, false, false), (false, true, false), (false, false, true)] {
                let mode = SoftwareUpdates.mode(
                    isHostingUnitTests: hosting, isUITesting: uiTesting, isMeasuringLaunch: measuring,
                    isDebug: isDebug, debugFeedURL: feed)
                #expect(mode == .off)
            }
        }
    }

    @Test("Release uses Info.plist's feed; Debug only with an http(s) feed argument")
    func releaseAndDebug() throws {
        func mode(isDebug: Bool, feed: String?) -> SoftwareUpdates.Mode {
            SoftwareUpdates.mode(
                isHostingUnitTests: false, isUITesting: false, isMeasuringLaunch: false, isDebug: isDebug,
                debugFeedURL: feed.flatMap { URL(string: $0) })
        }
        #expect(mode(isDebug: false, feed: nil) == .sparkle(feedURLOverride: nil))
        #expect(mode(isDebug: false, feed: "http://127.0.0.1/appcast.xml") == .sparkle(feedURLOverride: nil))
        #expect(mode(isDebug: true, feed: nil) == .off)
        #expect(mode(isDebug: true, feed: "file:///tmp/appcast.xml") == .off)
        let local = try #require(URL(string: "http://127.0.0.1:8000/appcast.xml"))
        #expect(mode(isDebug: true, feed: local.absoluteString) == .sparkle(feedURLOverride: local))
    }

    @Test("the hosted app's updater is inactive and can't check")
    func hostedAppIsInactive() {
        let updater = AppDelegate().updater
        #expect(updater is InactiveUpdater)
        #expect(!updater.isActive)
        #expect(!updater.canCheckForUpdates)
    }

    @Test("Info.plist: HTTPS feed, EdDSA key, verified archives and feed, nothing insecure")
    func infoPlist() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let feed = try #require((info["SUFeedURL"] as? String).flatMap { URL(string: $0) })
        #expect(feed.scheme == "https")
        #expect(feed.host() == "peep.now")
        #expect((info["SUPublicEDKey"] as? String)?.isEmpty == false)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        #expect(info["SURequireSignedFeed"] as? Bool == true)
        for key in [
            "SUAllowsInsecureUpdates", "SUEnableInstallerLauncherService", "SUEnableDownloaderService",
            "SUEnableSystemProfiling",
        ] {
            #expect(info[key] == nil, "\(key)")
        }
    }

    // MARK: Menu

    @Test("App menu > Check for Updates… comes right after About")
    func menuItem() throws {
        let menu = MainMenu.build()
        let app = try #require(menu.items.first?.submenu)
        let titles = app.items.map { $0.isSeparatorItem ? "-" : $0.title }
        #expect(Array(titles.prefix(4)).dropFirst() == ["-", "Check for Updates…", "-"])
        let item = try #require(app.items.first { $0.title == "Check for Updates…" })
        #expect(item.action == #selector(AppDelegate.checkForUpdates(_:)))
        #expect(item.target == nil)
    }

    @Test("Check for Updates… is enabled while the updater can check, and asks it to")
    func menuValidationAndAction() {
        let updater = FakeUpdater()
        let delegate = AppDelegate(updater: updater)
        let item = NSMenuItem("Check for Updates…", action: #selector(AppDelegate.checkForUpdates(_:)))

        #expect(delegate.validateMenuItem(item))
        updater.canCheckForUpdates = false
        #expect(!delegate.validateMenuItem(item))

        delegate.checkForUpdates(item)
        #expect(updater.checks == 1)
        #expect(updater.starts == 0, "only launch starts the updater")
    }

    @Test("nothing in a document window's responder chain answers Check for Updates…")
    func actionReachesDelegate() throws {
        let action = #selector(AppDelegate.checkForUpdates(_:))
        let controller = DocumentWindowController(themeSettings: ThemeSettings(isPersistent: false))
        let window = try #require(controller.window)
        var responder: NSResponder? = controller.coordinator.webView
        while let current = responder {
            #expect(!current.responds(to: action), "\(type(of: current)) answers \(action)")
            responder = current.nextResponder
        }
        #expect(!window.responds(to: action))
        #expect(!NSApplication.shared.responds(to: action))
        window.close()
    }

    // MARK: Settings

    /// A model over throwaway stores (nothing reaches the reader's settings) and `updater`.
    private func model(_ updater: FakeUpdater?) -> SettingsModel {
        let defaults = throwaway.defaults
        let viewer = DefaultViewer(
            workspace: FakeWorkspace(), defaults: defaults, applicationURL: URL(filePath: "/Applications/Peep.app"),
            bundleIdentifier: "now.peep.Peep", isSuppressed: true)
        return SettingsModel(
            appearanceSettings: AppearanceSettings(defaults: defaults, isPersistent: false),
            themeSettings: ThemeSettings(isPersistent: false),
            zoomSettings: ZoomSettings(defaults: defaults, isPersistent: false),
            contentWidthSettings: ContentWidthSettings(defaults: defaults, isPersistent: false),
            outlinePreference: OutlinePreference(defaults: defaults, isPersistent: false),
            markdownSettings: MarkdownSettings(defaults: defaults, isPersistent: false),
            updater: updater, defaultViewerOffer: DefaultViewerOfferController(viewer: viewer))
    }

    @Test("Settings reads and writes the updater's own settings")
    func settingsRows() {
        let updater = FakeUpdater()
        let model = model(updater)
        #expect(model.isUpdaterActive)
        #expect(!model.automaticallyChecksForUpdates)
        #expect(!model.allowsAutomaticUpdates)

        model.setAutomaticallyChecksForUpdates(true)
        #expect(updater.automaticallyChecksForUpdates)
        #expect(model.automaticallyChecksForUpdates)
        #expect(model.allowsAutomaticUpdates)

        model.setAutomaticallyDownloadsUpdates(true)
        #expect(updater.automaticallyDownloadsUpdates)
        #expect(model.automaticallyDownloadsUpdates)

        model.setAutomaticallyChecksForUpdates(false)
        #expect(!model.allowsAutomaticUpdates, "downloads need automatic checks")
    }

    @Test("Settings picks up changes made in Sparkle's own alerts when it refreshes")
    func settingsRefresh() {
        let updater = FakeUpdater()
        let model = model(updater)
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = true
        model.refresh()
        #expect(model.automaticallyChecksForUpdates)
        #expect(model.automaticallyDownloadsUpdates)
    }

    @Test("a model built without an updater uses an inactive one")
    func settingsDefault() {
        let model = model(nil)
        #expect(!model.isUpdaterActive)
        #expect(model.updater is InactiveUpdater)
    }
}
