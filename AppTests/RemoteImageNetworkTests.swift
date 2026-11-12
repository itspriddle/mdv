import AppKit
import Foundation
import PeepCore
import Testing
import WebKit

@testable import PeepApp

/// Remote images in a real `WKWebView`, observed from servers on 127.0.0.1 (never the
/// network): by default nothing leaves the viewer, not even through raw HTML the sanitizer
/// never sees; after opting in, `https:` images are fetched and nothing else is.
///
/// `https:` URLs point at a plain TCP server, so an allowed `https:` load shows up as a TLS
/// handshake (and then fails); that is enough to prove the request left.
@MainActor
@Suite("Remote images on the network", .serialized, .timeLimit(.minutes(1)))
struct RemoteImageNetworkTests {
    let coordinator = WebViewCoordinator()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered,
        defer: false)
    let folder: URL

    init() throws {
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.webView
        folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-app-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// The `peep-doc` base URL of a document in the test folder (as a window loads it).
    func baseURL() throws -> URL {
        let file = folder.appending(path: "README.md")
        try Data("x".utf8).write(to: file)
        return try #require(coordinator.documentURL(forFileAt: file))
    }

    /// Loads `page`, waits until every image has loaded or failed, then a little longer for
    /// stray fetches (fonts, frames, styles) to start.
    func show(html: String) async throws {
        try await coordinator.load(html: html, baseURL: try baseURL())
        _ = try await coordinator.webView.callAsyncJavaScript(
            "await Promise.all(Array.from(document.images).map((img) => img.decode().catch(() => null)));",
            arguments: [:], in: nil, contentWorld: AppScripts.world)
        try await Task.sleep(for: .milliseconds(500))
    }

    func evaluate(_ body: String) async throws -> Any? {
        try await coordinator.webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: AppScripts.world)
    }

    // MARK: Blocked by default

    @Test("by default, a document full of remote images makes no network request")
    func blockedByDefault() async throws {
        let http = try await LoopbackServer.start()
        let https = try await LoopbackServer.start()
        defer {
            http.stop()
            https.stop()
        }
        let content = DocumentContent(
            source: Self.remoteImageDocument(http: http, https: https), fallbackTitle: "README.md")
        try await show(html: content.page.html(theme: .github))
        #expect(http.connectionCount == 0, "\(http.connections.compactMap(\.requestLine))")
        #expect(https.connectionCount == 0)
        // The blocked images show as labeled placeholders, and no <img> points anywhere remote.
        let placeholders = try await evaluate("return document.querySelectorAll('.remote-image').length;")
        #expect((placeholders as? NSNumber)?.intValue == content.page.blockedRemoteImages.count)
        #expect(content.page.blockedRemoteImages.count == 13)
        let remoteImages = try await evaluate(
            "return Array.from(document.images).filter((img) => /^https?:/.test(img.src)).length;")
        #expect((remoteImages as? NSNumber)?.intValue == 0)
    }

    @Test("the viewer CSP alone blocks images, frames, styles, fonts, and media in raw HTML")
    func cspBlocksEverything() async throws {
        let server = try await LoopbackServer.start()
        defer { server.stop() }
        try await show(html: Self.hostilePage(csp: .viewer, server: server))
        #expect(server.connectionCount == 0, "\(server.connections.compactMap(\.requestLine))")
    }

    @Test("control: without a CSP the same page does fetch, so the tests above can fail")
    func controlWithoutCSP() async throws {
        let server = try await LoopbackServer.start()
        defer { server.stop() }
        try await show(html: Self.hostilePage(csp: nil, server: server))
        let paths = Set(server.connections.compactMap(\.requestLine))
        #expect(paths.contains("GET /img.png HTTP/1.1"), "\(paths)")
        #expect(paths.contains("GET /link.css HTTP/1.1"), "\(paths)")
        #expect(paths.contains("GET /font.woff2 HTTP/1.1"), "\(paths)")
        #expect(paths.contains("GET /audio.mp3 HTTP/1.1"), "\(paths)")
        // Frames, objects, and embeds are also stopped by the navigation policy (sub-frame
        // navigations are cancelled) and by WebKit (no plug-ins), so they never fetch.
        #expect(paths.count >= 12, "\(paths)")
    }

    // MARK: Opted in

    @Test("after opting in, https images are fetched and http images are not")
    func optedIn() async throws {
        let http = try await LoopbackServer.start()
        let https = try await LoopbackServer.start()
        defer {
            http.stop()
            https.stop()
        }
        let content = DocumentContent(
            source: Self.remoteImageDocument(http: http, https: https), fallbackTitle: "README.md")
        let page = content.page(allowingRemoteImages: true)
        #expect(page.contentSecurityPolicy == .viewerAllowingRemoteImages)
        try await show(html: page.html(theme: .github))
        #expect(https.connectionCount > 0)
        #expect(https.connections.allSatisfy { $0.isTLS })
        #expect(http.connectionCount == 0, "\(http.connections.compactMap(\.requestLine))")
        let csp = try await evaluate(
            "return document.querySelector('meta[http-equiv=\"Content-Security-Policy\"]').content;")
        #expect(csp as? String == ContentSecurityPolicy.viewerAllowingRemoteImages.header)
    }

    @Test("the opt-in CSP still blocks http images and every non-image https load")
    func optInCSPAllowsOnlyHTTPSImages() async throws {
        let http = try await LoopbackServer.start()
        let other = try await LoopbackServer.start()
        let image = try await LoopbackServer.start()
        defer {
            http.stop()
            other.stop()
            image.stop()
        }
        // Every kind of load over http; every non-image load over https; one https image.
        let httpURL = { (path: String) in http.url(path) }
        let otherURL = { (path: String) in other.url(path, https: true) }
        let html = Self.page(
            csp: .viewerAllowingRemoteImages,
            [
                Self.imageLoads(httpURL), Self.otherLoads(httpURL), Self.otherLoads(otherURL),
                ("", "<img src=\"\(image.url("/ok.png", https: true))\" alt=\"ok\">"),
            ])
        try await show(html: html)
        #expect(http.connectionCount == 0, "\(http.connections.compactMap(\.requestLine))")
        #expect(other.connectionCount == 0)
        #expect(image.connectionCount > 0)
    }

    // MARK: Windows

    /// Opens `source` as a document with a window, once the page has loaded.
    func openWindow(_ source: String, name: String = "README.md") async throws -> (
        MarkdownDocument, DocumentWindowController
    ) {
        let file = folder.appending(path: name)
        try Data(source.utf8).write(to: file)
        let document = try MarkdownDocument(contentsOf: file, ofType: "net.daringfireball.markdown")
        document.makeWindowControllers()
        let controller = try #require(document.windowControllers.first as? DocumentWindowController)
        try await until("the first load") { controller.coordinator.hasLoadedPage }
        return (document, controller)
    }

    func pageCSP(_ controller: DocumentWindowController) async throws -> String? {
        try await controller.coordinator.webView.callAsyncJavaScript(
            "return document.querySelector('meta[http-equiv=\"Content-Security-Policy\"]').content;",
            arguments: [:], in: nil, contentWorld: AppScripts.world) as? String
    }

    func until(_ what: String, timeout: Duration = .seconds(5), _ condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while try await !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("timed out waiting for \(what)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Load opts in one window only, keeps its position, and survives live reload")
    func windowOptIn() async throws {
        let server = try await LoopbackServer.start()
        defer { server.stop() }
        let paragraphs = (1...150).map { "Paragraph \($0)." }.joined(separator: "\n\n")
        let source = "![badge](\(server.url("/badge.png", https: true)))\n\n" + paragraphs
        let (document, controller) = try await openWindow(source)
        defer { document.close() }
        let (other, otherController) = try await openWindow(source, name: "OTHER.md")
        defer { other.close() }

        // Blocked: the bar offers 1 image; the page has the viewer CSP and made no request.
        #expect(
            controller.remoteImages.bar(for: document.content?.page)?.detail == "1 image from 127.0.0.1:\(server.port)")
        #expect(try await pageCSP(controller) == ContentSecurityPolicy.viewer.header)
        try await controller.coordinator.scroll(toSourceLine: 101)
        try await Task.sleep(for: .milliseconds(300))
        #expect(server.connectionCount == 0)

        controller.loadRemoteImages(nil)
        #expect(controller.remoteImages.isAllowed)
        #expect(controller.remoteImages.bar(for: document.content?.page) == nil)
        try await until("the opt-in CSP") {
            try await pageCSP(controller) == ContentSecurityPolicy.viewerAllowingRemoteImages.header
        }
        try await until("the https image request") { server.connectionCount > 0 }
        try await until("the reading position restored") {
            abs(try await controller.coordinator.currentSourceLine() - 101) < 2
        }

        // The other window is untouched.
        #expect(!otherController.remoteImages.isAllowed)
        #expect(otherController.remoteImages.bar(for: other.content?.page) != nil)
        #expect(try await pageCSP(otherController) == ContentSecurityPolicy.viewer.header)

        // A live reload of the opted-in window keeps the opt-in and the CSP, in place.
        let before = server.connectionCount
        let updated = source.replacingOccurrences(of: "/badge.png", with: "/badge2.png") + "\n\nNew paragraph."
        try Data(updated.utf8).write(to: folder.appending(path: "README.md"))
        try await until("the reload") {
            try await controller.coordinator.webView.callAsyncJavaScript(
                "return document.body.textContent.includes('New paragraph.');", arguments: [:], in: nil,
                contentWorld: AppScripts.world) as? Bool == true
        }
        #expect(controller.remoteImages.isAllowed)
        #expect(try await pageCSP(controller) == ContentSecurityPolicy.viewerAllowingRemoteImages.header)
        let placeholders = try await controller.coordinator.webView.callAsyncJavaScript(
            "return document.querySelectorAll('.remote-image').length;", arguments: [:], in: nil,
            contentWorld: AppScripts.world)
        #expect((placeholders as? NSNumber)?.intValue == 0)
        try await until("the reloaded https image request") { server.connectionCount > before }
    }

    @Test("documents with only http images offer no bar: opting in wouldn't load them")
    func httpOnlyHasNoBar() {
        let content = DocumentContent(source: "![a](http://example.invalid/a.png)", fallbackTitle: "a.md")
        #expect(content.page.blockedRemoteImages.count == 1)
        #expect(content.remoteImagesPage == nil)
        #expect(RemoteImageOptIn().bar(for: content.page) == nil)
        #expect(content.page(allowingRemoteImages: true) == content.page)
    }
}
