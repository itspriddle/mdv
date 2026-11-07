import AppKit
import MdvCore
import Testing
import WebKit

@testable import MdvApp

/// Share and drags out of the page carry `file:` URLs, never the window's `mdv-doc` URLs, as
/// Copy Link does (#42).
@MainActor
@Suite("Share and drags", .serialized, .timeLimit(.minutes(1)))
final class SharedLinksTests: DocumentWindowTestCase {
    /// Dispatches `contextmenu` on the first element matching `selector` and waits for the
    /// script's report of what it was opened on.
    func openContextMenu(onElementMatching selector: String, in controller: DocumentWindowController) async throws {
        let coordinator = controller.coordinator
        coordinator.contextMenuTarget = ContextMenuTarget(link: URL(string: "about:pending"))
        _ = try await coordinator.webView.callAsyncJavaScript(
            """
            document.querySelector(selector).dispatchEvent(new MouseEvent("contextmenu", { bubbles: true }));
            return true;
            """, arguments: ["selector": selector], in: nil, contentWorld: AppScripts.world)
        for _ in 0..<100 where coordinator.contextMenuTarget.link?.scheme == "about" {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(coordinator.contextMenuTarget.link?.scheme != "about", "the script reported the target")
    }

    @Test("Share on a local link or image shares the file: URL; other targets keep WebKit's Share")
    func shareItems() async throws {
        defer { closeAll() }
        let source = "[guide](sub/guide.md#set-up) [site](https://example.com/)\n\n![pic](pic.png)\n\nplain"
        let (_, controller) = try await open(source)
        let coordinator = controller.coordinator

        try await openContextMenu(onElementMatching: "a[href^='sub/']", in: controller)
        let link = try #require(coordinator.contextMenuShareItems()?.first)
        #expect(link.isFileURL && link.absoluteString.hasSuffix("/sub/guide.md#set-up"), "\(link)")

        try await openContextMenu(onElementMatching: "img", in: controller)
        let image = try #require(coordinator.contextMenuShareItems()?.first)
        #expect(image.isFileURL && image.lastPathComponent == "pic.png", "\(image)")

        try await openContextMenu(onElementMatching: "a[href^='https:']", in: controller)
        #expect(coordinator.contextMenuShareItems() == nil)
        try await openContextMenu(onElementMatching: "p:last-of-type", in: controller)
        #expect(coordinator.contextMenuShareItems() == nil)

        coordinator.contextMenuTarget = ContextMenuTarget(
            link: URL(string: "mdv-doc://00000000-0000-0000-0000-000000000000/etc/hosts"))
        #expect(coordinator.contextMenuShareItems() == [], "another window's URL shares nothing")
    }

    @Test("the context menu's Share is replaced, removed, or kept")
    func shareMenuItem() throws {
        func menu() -> NSMenu {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
            let share = NSMenuItem(title: "WebKit Share", action: nil, keyEquivalent: "")
            share.identifier = NSUserInterfaceItemIdentifier(WebViewContextMenu.shareIdentifier)
            menu.addItem(share)
            menu.addItem(NSMenuItem(title: "Services", action: nil, keyEquivalent: ""))
            return menu
        }
        let kept = menu()
        WebViewContextMenu.replaceShare(in: kept, sharing: nil)
        #expect(kept.items.map(\.title) == ["Copy", "WebKit Share", "Services"])

        let removed = menu()
        WebViewContextMenu.replaceShare(in: removed, sharing: [])
        #expect(removed.items.map(\.title) == ["Copy", "Services"])

        let replaced = menu()
        WebViewContextMenu.replaceShare(in: replaced, sharing: [URL(filePath: "/tmp/guide.md")])
        #expect(replaced.items.count == 3)
        let share = replaced.items[1]
        #expect(share.title != "WebKit Share")
        #expect(share.identifier?.rawValue == WebViewContextMenu.shareIdentifier)
        #expect(share.submenu != nil || share.action != nil)
    }

    @Test("a drag's pasteboard carries file: URLs, never mdv-doc")
    func dragPasteboard() async throws {
        defer { closeAll() }
        let (_, controller) = try await open("plain")
        let coordinator = controller.coordinator
        let token = coordinator.localResources.token
        let drag = NSPasteboard.withUniqueName()
        defer { drag.releaseGlobally() }
        let url = NSPasteboard.PasteboardType.URL
        let name = NSPasteboard.PasteboardType("public.url-name")
        drag.declareTypes([url, name, .string], owner: nil)
        drag.setString("mdv-doc://\(token)/tmp/guide.md#a", forType: url)
        drag.setString("Guide", forType: name)
        drag.setString("mdv-doc://\(token)/tmp/guide.md#a", forType: .string)

        coordinator.webView.dragPasteboardHandler?(drag)
        #expect(drag.string(forType: url) == "file:///tmp/guide.md#a")
        #expect(drag.string(forType: name) == "Guide")
        #expect(drag.string(forType: .string) == "file:///tmp/guide.md#a")
        for type in drag.types ?? [] {
            #expect(drag.string(forType: type)?.lowercased().contains("mdv-doc") != true, "\(type.rawValue)")
        }
    }

    // MARK: Copy Image

    /// Writes a 4 x 3 PNG and a 20 x 10 SVG into the document's folder.
    func writeImages() throws {
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try #require(rep.representation(using: .png, properties: [:])).write(to: folder.appending(path: "pic.png"))
        try Data(
            #"<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"><rect width="20" height="10" fill="red"/></svg>"#
                .utf8
        ).write(to: folder.appending(path: "shape.svg"))
    }

    /// Waits until every image on the page has loaded.
    func waitForImages(in controller: DocumentWindowController) async throws {
        for _ in 0..<100 {
            let loaded = try await controller.coordinator.callBridge(
                "return [...document.images].every((image) => image.complete && image.naturalWidth > 0);")
            if loaded as? Bool == true {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("images didn't load")
    }

    @Test("Copy Image on a local image copies the file and a PNG, never an mdv-doc URL")
    func copyImage() async throws {
        defer { closeAll() }
        try writeImages()
        let (_, controller) = try await open("![png](pic.png) ![svg](shape.svg)\n\n[link](guide.md)")
        let coordinator = controller.coordinator
        try await waitForImages(in: controller)

        try await openContextMenu(onElementMatching: "img[alt='png']", in: controller)
        #expect(coordinator.contextMenuLocalImage != nil)
        #expect(await coordinator.copyContextMenuImage(to: pasteboard))
        #expect(pasteboard.types?.first == .png)
        #expect(pasteboard.data(forType: .png) == (try Data(contentsOf: folder.appending(path: "pic.png"))))

        try await openContextMenu(onElementMatching: "img[alt='svg']", in: controller)
        #expect(await coordinator.copyContextMenuImage(to: pasteboard))
        let svgType = NSPasteboard.PasteboardType("public.svg-image")
        #expect(pasteboard.types?.first == .png && pasteboard.types?.contains(svgType) == true)
        #expect(pasteboard.data(forType: svgType) == (try Data(contentsOf: folder.appending(path: "shape.svg"))))
        let png = try #require(pasteboard.data(forType: .png))
        let drawn = try #require(NSBitmapImageRep(data: png))
        #expect(drawn.pixelsWide >= 20 && drawn.pixelsHigh >= 10, "\(drawn.pixelsWide) x \(drawn.pixelsHigh)")

        for type in pasteboard.types ?? [] {
            let data = pasteboard.data(forType: type) ?? Data()
            #expect(data.range(of: Data("mdv-doc".utf8)) == nil, "\(type.rawValue)")
        }

        try await openContextMenu(onElementMatching: "a", in: controller)
        #expect(coordinator.contextMenuLocalImage == nil, "not an image: WebKit's Copy Image stays")
        #expect(await !coordinator.copyContextMenuImage(to: pasteboard))
    }

    @Test("PNG data URLs are decoded; anything else is refused")
    func pngDataURL() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
        let url = "data:image/png;base64," + png.base64EncodedString()
        #expect(WebViewCoordinator.pngData(fromDataURL: url) == png)
        #expect(WebViewCoordinator.pngData(fromDataURL: "data:image/png;base64,") == nil)
        #expect(WebViewCoordinator.pngData(fromDataURL: "data:image/png;base64,!!!") == nil)
        #expect(WebViewCoordinator.pngData(fromDataURL: "data:image/jpeg;base64," + png.base64EncodedString()) == nil)
        #expect(
            WebViewCoordinator.pngData(
                fromDataURL: "data:image/png;base64," + Data("GIF89a".utf8).base64EncodedString()) == nil)
    }
}
