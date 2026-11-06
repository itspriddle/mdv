import AppKit
import Testing

@testable import MdvApp

/// Zoom (#26): the app-wide level, windows following it, pinch magnification, and the menus.
@MainActor
@Suite("Zoom", .serialized, .timeLimit(.minutes(1)))
final class ZoomTests: DocumentWindowTestCase {
    // MARK: Zoom levels and settings

    @Test("zoom steps up and down through the levels and stops at the ends")
    func steps() {
        #expect(PageZoom.larger(than: 1) == 1.1)
        #expect(PageZoom.smaller(than: 1) == 0.9)
        #expect(PageZoom.larger(than: 1.05) == 1.1)
        #expect(PageZoom.smaller(than: 1.05) == 1.0)
        #expect(PageZoom.larger(than: 3) == nil)
        #expect(PageZoom.smaller(than: 0.5) == nil)
        #expect(PageZoom.valid(.nan) == nil)
        #expect(PageZoom.valid(.infinity) == nil)
        #expect(PageZoom.valid(0) == nil)
        #expect(PageZoom.valid(10) == nil)
        #expect(PageZoom.valid(1.25) == 1.25)
    }

    @Test("the app-wide level persists, ignores bad stored values, and posts changes")
    func settingsPersist() {
        let zoom = settings()
        #expect(zoom.level == 1)
        var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: ZoomSettings.didChangeNotification, object: zoom, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        zoom.level = 1.5
        #expect(defaults.double(forKey: ZoomSettings.key) == 1.5)
        #expect(settings().level == 1.5, "a new instance reads the persisted level")
        zoom.level = 1.5
        #expect(posts == 1, "setting the same level posts nothing")
        zoom.level = 1
        #expect(defaults.object(forKey: ZoomSettings.key) == nil, "actual size removes the key")
        defaults.set(99.0, forKey: ZoomSettings.key)
        #expect(zoom.level == 1)
        defaults.set("big", forKey: ZoomSettings.key)
        #expect(zoom.level == 1)
    }

    @Test("UI-test settings stay in memory")
    func settingsInMemory() {
        let zoom = ZoomSettings(defaults: defaults, isPersistent: false)
        zoom.level = 2
        #expect(zoom.level == 2)
        #expect(defaults.object(forKey: ZoomSettings.key) == nil)
    }

    // MARK: Zoom in windows

    @Test("zoom commands change every window, survive a reload, and Actual Size resets pinch")
    func windowsFollow() async throws {
        defer { closeAll() }
        let zoom = settings()
        let (_, first) = try await open(zoomSettings: zoom)
        let (_, second) = try await open(name: "other.md", zoomSettings: zoom)
        #expect(first.coordinator.webView.allowsMagnification, "pinch-to-zoom is on")
        #expect(first.coordinator.webView.pageZoom == 1)

        first.zoomInDocument(nil)
        first.zoomInDocument(nil)
        #expect(zoom.level == 1.25)
        #expect(first.coordinator.webView.pageZoom == 1.25)
        #expect(second.coordinator.webView.pageZoom == 1.25)
        second.zoomOutDocument(nil)
        #expect(first.coordinator.webView.pageZoom == 1.1)

        // The zoom reflows the page: the CSS viewport narrows.
        let width = try #require(
            try await first.coordinator.webView.callAsyncJavaScript(
                "return window.innerWidth;", arguments: [:], in: nil, contentWorld: AppScripts.world) as? NSNumber)
        #expect(abs(width.doubleValue - first.coordinator.webView.bounds.width / 1.1) < 2)

        // A new window starts at the app-wide level; a full reload keeps it.
        let (document, third) = try await open(name: "third.md", zoomSettings: zoom)
        #expect(third.coordinator.webView.pageZoom == 1.1)
        try await third.coordinator.load(try #require(document.content).page, baseURL: nil)
        #expect(third.coordinator.webView.pageZoom == 1.1)

        // Pinch is the window's own: Actual Size clears it along with the app-wide level.
        first.coordinator.webView.magnification = 2
        #expect(second.coordinator.webView.magnification == 1)
        first.resetDocumentZoom(nil)
        #expect(first.coordinator.webView.magnification == 1)
        #expect(zoom.level == 1)
        #expect(second.coordinator.webView.pageZoom == 1)
    }

    @Test("zoom items are disabled at the ends and Actual Size at actual size")
    func zoomValidation() async throws {
        defer { closeAll() }
        let zoom = settings()
        let (_, controller) = try await open(zoomSettings: zoom)
        let zoomIn = try #require(item("Zoom In", in: "View"))
        let zoomOut = try #require(item("Zoom Out", in: "View"))
        let actualSize = try #require(item("Actual Size", in: "View"))
        #expect(controller.validateMenuItem(zoomIn))
        #expect(controller.validateMenuItem(zoomOut))
        #expect(!controller.validateMenuItem(actualSize))
        zoom.level = 3
        #expect(!controller.validateMenuItem(zoomIn))
        #expect(controller.validateMenuItem(actualSize))
        zoom.level = 0.5
        #expect(!controller.validateMenuItem(zoomOut))
        zoom.level = 1
        controller.coordinator.webView.magnification = 1.5
        #expect(controller.validateMenuItem(actualSize))
    }

    @Test("window restoration keeps the pinch magnification and rejects bad values")
    func magnificationRestoration() async throws {
        defer { closeAll() }
        let (_, controller) = try await open()
        controller.coordinator.webView.magnification = 1.5
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        controller.encodeZoomState(with: archiver)
        archiver.finishEncoding()

        let (_, restored) = try await open(name: "restored.md")
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        restored.restoreZoomState(with: unarchiver)
        #expect(restored.coordinator.webView.magnification == 1.5)

        #expect(DocumentWindowController.validMagnification(.nan) == nil)
        #expect(DocumentWindowController.validMagnification(100) == nil)
        #expect(DocumentWindowController.validMagnification(0) == nil)
        #expect(DocumentWindowController.validMagnification(2) == 2)

        let unchanged = NSKeyedArchiver(requiringSecureCoding: true)
        restored.coordinator.webView.magnification = 1
        restored.encodeZoomState(with: unchanged)
        unchanged.finishEncoding()
        let reader = try NSKeyedUnarchiver(forReadingFrom: unchanged.encodedData)
        #expect(!reader.containsValue(forKey: DocumentWindowController.magnificationStateKey))
    }

    // MARK: Menus

    @Test("commands sit in the standard menus with the standard shortcuts")
    func menus() throws {
        let menu = MainMenu.build()
        let view = try #require(menu.item(withTitle: "View")?.submenu)
        let zoomItems = view.items.filter { $0.action == #selector(DocumentWindowController.zoomInDocument(_:)) }
        #expect(zoomItems.map(\.keyEquivalent) == ["+", "="])
        #expect(zoomItems.map(\.isHidden) == [false, true])
        #expect(zoomItems.last?.allowsKeyEquivalentWhenHidden == true)
        #expect(view.item(withTitle: "Zoom Out")?.keyEquivalent == "-")
        #expect(view.item(withTitle: "Actual Size")?.keyEquivalent == "0")

        let file = try #require(menu.item(withTitle: "File")?.submenu)
        let print = try #require(file.item(withTitle: "Print…"))
        #expect(print.action == #selector(NSDocument.printDocument(_:)))
        #expect(print.keyEquivalent == "p" && print.keyEquivalentModifierMask == .command)
        let pageSetup = try #require(file.item(withTitle: "Page Setup…"))
        #expect(pageSetup.action == #selector(NSDocument.runPageLayout(_:)))
        #expect(pageSetup.keyEquivalentModifierMask == [.command, .shift])

        let edit = try #require(menu.item(withTitle: "Edit")?.submenu)
        let titles = edit.items.map(\.title)
        let copyIndex = try #require(titles.firstIndex(of: "Copy"))
        let sourceIndex = try #require(titles.firstIndex(of: "Copy Markdown Source"))
        #expect(copyIndex < sourceIndex)
        #expect(titles.contains("Copy as HTML"))
    }

    /// With no document window, nothing in the responder chain handles these actions, so AppKit
    /// disables them.
    @Test("document commands have no handler outside a document window")
    func noDocumentWindow() {
        for action in [
            #selector(DocumentWindowController.zoomInDocument(_:)),
            #selector(DocumentWindowController.copyMarkdownSource(_:)),
            #selector(DocumentWindowController.copyAsHTML(_:)),
            #selector(NSDocument.printDocument(_:)),
        ] {
            #expect(!NSApp.responds(to: action))
            #expect(!(NSApp.delegate?.responds(to: action) ?? false))
        }
    }
}
