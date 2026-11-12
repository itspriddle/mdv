import AppKit
import ImageIO
import PeepCore
import Testing
import UniformTypeIdentifiers
import WebKit

@testable import PeepApp

/// Hosted `WKWebView` tests: relative images load through the `peep-doc` scheme handler, and
/// nothing outside the policy does. The policy itself is unit tested in `PeepCoreTests`.
@MainActor
@Suite("LocalResourceSchemeHandler", .serialized, .timeLimit(.minutes(1)))
struct LocalResourceSchemeHandlerTests {
    let coordinator = WebViewCoordinator()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered,
        defer: false)
    /// `repo/` (a git work tree) holds the document in `repo/docs/`; `outside/` is beyond it.
    let folder: URL

    init() throws {
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.webView
        let base = FileManager.default.temporaryDirectory.appending(path: "peep-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // The real path (`/private/var/...`), as the policy reports it.
        let real = try #require(realpath(base.path(percentEncoded: false), nil))
        defer { free(real) }
        folder = URL(filePath: String(cString: real), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: folder.appending(path: "repo/.git"), withIntermediateDirectories: true)
    }

    func write(_ relative: String, _ data: Data) throws {
        let url = folder.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// Writes `source` as `repo/docs/README.md` and loads it the way a document window does.
    func loadDocument(_ source: String) async throws {
        let fileURL = folder.appending(path: "repo/docs/README.md")
        try write("repo/docs/README.md", Data(source.utf8))
        let baseURL = try #require(coordinator.documentURL(forFileAt: fileURL))
        try await coordinator.load(DocumentContent(source: source, fallbackTitle: "README.md").page, baseURL: baseURL)
    }

    /// Each `<img>`'s alt text and natural width once it has loaded or failed (0 = broken).
    func imageWidths() async throws -> [String: Int] {
        let result = try await coordinator.webView.callAsyncJavaScript(
            """
            const images = Array.from(document.images);
            await Promise.all(images.map((img) => img.decode().catch(() => null)));
            return Object.fromEntries(images.map((img) => [img.alt, img.naturalWidth]));
            """, arguments: [:], in: nil, contentWorld: AppScripts.world)
        let widths = try #require(result as? [String: NSNumber])
        return widths.mapValues(\.intValue)
    }

    static func raster(_ type: UTType, width: Int, height: Int) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// A 1x1 lossless WebP (ImageIO decodes WebP but can't encode it).
    static let webp = Data(base64Encoded: "UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==") ?? Data()

    static func svg(width: Int, extra: String = "") -> Data {
        Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" \
            width="\(width)" height="10">\(extra)<rect width="\(width)" height="10" fill="teal"/></svg>
            """.utf8)
    }

    @Test("relative PNG, JPEG, GIF, WebP, and SVG images render, including from other folders in the repo")
    func rendersRelativeImages() async throws {
        try write("repo/docs/same.png", try Self.raster(.png, width: 11, height: 5))
        try write("repo/docs/img/sub.jpg", try Self.raster(.jpeg, width: 12, height: 5))
        try write("repo/images/up.gif", try Self.raster(.gif, width: 13, height: 5))
        try write("repo/images/up.webp", Self.webp)
        try write("repo/docs/img/deep/shape.svg", Self.svg(width: 14))
        try write("repo/docs/with space.png", try Self.raster(.png, width: 15, height: 5))
        try await loadDocument(
            """
            ![png](same.png) ![jpeg](img/sub.jpg) ![gif](../images/up.gif) ![webp](../images/up.webp)
            ![svg](./img/deep/shape.svg) ![space](<with space.png>) ![query](same.png?v=2)
            """)
        #expect(
            try await imageWidths() == [
                "png": 11, "jpeg": 12, "gif": 13, "webp": 1, "svg": 14, "space": 15, "query": 11,
            ])
    }

    @Test("images outside the root, non-images, missing files, and file: URLs show as broken")
    func refused() async throws {
        let png = try Self.raster(.png, width: 9, height: 9)
        try write("outside/secret.png", png)
        try write("repo/docs/fake.png", Data("not an image".utf8))
        try write("repo/docs/notes.txt", png)
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "repo/docs/link.png"),
            withDestinationURL: folder.appending(path: "outside/secret.png"))
        let fileURL = folder.appending(path: "outside/secret.png").absoluteString
        try await loadDocument(
            """
            ![up](../../outside/secret.png) ![encoded](%2e%2e/%2e%2e/outside/secret.png)
            ![link](link.png) ![fake](fake.png) ![text](notes.txt) ![missing](missing.png)
            ![file](\(fileURL))
            """)
        let widths = try await imageWidths()
        #expect(widths.count == 7)
        #expect(widths.values.allSatisfy { $0 == 0 }, "\(widths)")
    }

    @Test("an SVG shown as an image runs no scripts and loads no subresources")
    func svgIsInert() async throws {
        try write("repo/docs/probe.png", try Self.raster(.png, width: 3, height: 3))
        let active = """
            <script>fetch("probe.png?from=script");</script>\
            <image href="probe.png?from=image" width="3" height="3"/>\
            <image xlink:href="probe.png?from=xlink" width="3" height="3"/>\
            <foreignObject width="3" height="3"><img xmlns="http://www.w3.org/1999/xhtml" \
            src="probe.png?from=foreign"/></foreignObject>
            """
        try write("repo/docs/active.svg", Self.svg(width: 20, extra: active))
        try await loadDocument("![active](active.svg)")
        #expect(try await imageWidths() == ["active": 20])
        try await Task.sleep(for: .milliseconds(200))
        let requested = coordinator.localResources.requestedURLs.map(\.lastPathComponent)
        #expect(requested == ["active.svg"])
    }

    @Test("without a file URL, nothing is scoped and nothing is served")
    func noDocument() async throws {
        #expect(coordinator.documentURL(forFileAt: nil) == nil)
        #expect(coordinator.localResources.policy == nil)
    }

    @Test("the document URL uses the window's token and the document's real path")
    func documentURL() throws {
        let fileURL = folder.appending(path: "repo/docs/README.md")
        try write("repo/docs/README.md", Data())
        let url = try #require(coordinator.documentURL(forFileAt: fileURL))
        #expect(url.scheme == DocumentURLScheme.name)
        #expect(url.host() == coordinator.localResources.token)
        #expect(
            DocumentURLScheme.filePath(from: url, token: coordinator.localResources.token)
                == fileURL.path(percentEncoded: false))
        #expect(coordinator.localResources.policy?.root == folder.appending(path: "repo").path(percentEncoded: false))
    }

    @Test("each window has its own token")
    func tokens() {
        #expect(coordinator.localResources.token != WebViewCoordinator().localResources.token)
    }
}
