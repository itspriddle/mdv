import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import MdvApp

/// Records calls instead of changing Launch Services.
@MainActor
final class FakeWorkspace: DefaultApplicationWorkspace {
    var handlers: [UTType: String] = [:]
    var setCalls: [(URL, UTType)] = []
    var setError: (any Error)?
    /// Whether a successful `set` changes the handler (false simulates a change that didn't stick).
    var appliesChanges = true

    func defaultApplicationBundleIdentifier(toOpen contentType: UTType) -> String? {
        handlers[contentType]
    }

    func setDefaultApplication(at applicationURL: URL, toOpen contentType: UTType) async throws {
        setCalls.append((applicationURL, contentType))
        if let setError {
            throw setError
        }
        if appliesChanges {
            handlers[contentType] = "com.itspriddle.mdv"
        }
    }

    /// Makes `bundleIdentifier` the default for every Markdown type mdv declares.
    func setHandler(_ bundleIdentifier: String, for contentTypes: [UTType] = DefaultViewer.contentTypes) {
        for contentType in contentTypes {
            handlers[contentType] = bundleIdentifier
        }
    }
}

struct DeclinedByUser: Error {}

@MainActor
@Suite("DefaultViewer")
struct DefaultViewerTests {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
    let workspace = FakeWorkspace()
    let defaults: UserDefaults
    let suiteName = "DefaultViewerTests.\(UUID().uuidString)"
    var date = Date(timeIntervalSince1970: 1_000_000)

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        workspace.setHandler("com.example.other")
    }

    func viewer(suppressed: Bool = false, at date: Date? = nil) -> DefaultViewer {
        let now = date ?? self.date
        return DefaultViewer(
            workspace: workspace, defaults: defaults, applicationURL: URL(filePath: "/Applications/mdv.app"),
            bundleIdentifier: "com.itspriddle.mdv", isSuppressed: suppressed, now: { now })
    }

    @Test("offers when another app is the default")
    func offersWhenNotDefault() {
        #expect(viewer().shouldOffer)
    }

    @Test("doesn't offer when mdv is already the default")
    func noOfferWhenDefault() {
        workspace.setHandler("com.itspriddle.mdv")
        let viewer = viewer()
        #expect(viewer.isDefault)
        #expect(!viewer.shouldOffer)
    }

    @Test("offers until mdv is the default for every declared Markdown type")
    func offersUntilDefaultForEveryType() {
        #expect(DefaultViewer.contentTypes.count > 1)
        workspace.setHandler("com.itspriddle.mdv", for: [Self.markdown])
        let viewer = viewer()
        #expect(!viewer.isDefault)
        #expect(viewer.shouldOffer)
    }

    @Test("offers when no app is registered")
    func offersWhenNoHandler() {
        workspace.handlers = [:]
        #expect(viewer().shouldOffer)
    }

    @Test("UI tests suppress the offer")
    func suppressed() {
        #expect(!viewer(suppressed: true).shouldOffer)
    }

    @Test("offers at most once per launch")
    func oncePerLaunch() {
        let viewer = viewer()
        viewer.offerShown()
        #expect(!viewer.shouldOffer)
    }

    @Test("Not Now snoozes the offer across launches")
    func notNowSnoozes() async throws {
        let first = viewer()
        first.offerShown()
        try await first.respond(.notNow)
        #expect(!viewer(at: date.addingTimeInterval(24 * 60 * 60)).shouldOffer)
        #expect(viewer(at: date.addingTimeInterval(DefaultViewer.snoozeInterval)).shouldOffer)
        #expect(workspace.setCalls.isEmpty)
    }

    @Test("Don't Ask Again is permanent")
    func dontAskAgain() async throws {
        let first = viewer()
        first.offerShown()
        try await first.respond(.dontAskAgain)
        #expect(!viewer(at: date.addingTimeInterval(10 * DefaultViewer.snoozeInterval)).shouldOffer)
        #expect(workspace.setCalls.isEmpty)
    }

    @Test("Make Default sets mdv for every Markdown type")
    func makeDefault() async throws {
        let viewer = viewer()
        try await viewer.respond(.makeDefault)
        #expect(workspace.setCalls.map(\.1) == DefaultViewer.contentTypes)
        #expect(workspace.setCalls.allSatisfy { $0.0 == URL(filePath: "/Applications/mdv.app") })
        workspace.setHandler("com.itspriddle.mdv")
        #expect(viewer.isDefault)
    }

    @Test("a declined system confirmation throws and leaves the default")
    func declined() async {
        workspace.setError = DeclinedByUser()
        let viewer = viewer()
        await #expect(throws: DeclinedByUser.self) { try await viewer.makeDefault() }
        #expect(!viewer.isDefault)
    }

    @Test("a change that doesn't stick throws notApplied")
    func notApplied() async {
        workspace.appliesChanges = false
        await #expect(throws: DefaultViewer.Failure.notApplied) { try await viewer().makeDefault() }
    }

    @Test("menu item is enabled until mdv is the default, then checked")
    func menuValidation() {
        let controller = DefaultViewerOfferController(viewer: viewer())
        let item = NSMenuItem("Make", action: #selector(AppDelegate.makeDefaultMarkdownViewer(_:)))
        #expect(controller.validateMenuItem(item))
        #expect(item.state == .off)
        workspace.setHandler("com.itspriddle.mdv")
        #expect(!controller.validateMenuItem(item))
        #expect(item.state == .on)
    }

    @Test("the app menu has the item")
    func menuItem() {
        let menu = MainMenu.build(contributions: [DefaultViewerMenu.self])
        let item = menu.items.first?.submenu?.item(withTitle: "Make mdv the Default Markdown Viewer")
        #expect(item?.action == #selector(AppDelegate.makeDefaultMarkdownViewer(_:)))
    }
}
