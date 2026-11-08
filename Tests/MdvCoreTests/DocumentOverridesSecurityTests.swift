import Foundation
import Testing

@testable import MdvCore

/// The security boundary of frontmatter overrides (#54, VISION's security model): a document can
/// choose among presentation options only. Each test names a safety setting and proves a document
/// can't change it.
@Suite("Document overrides: safety settings")
struct DocumentOverridesSecurityTests {
    /// The viewer's options: sanitizing on, remote images blocked, root-relative URLs resolved,
    /// source lines on.
    static var viewerOptions: RenderOptions {
        var options = RenderOptions()
        options.sourceLines = true
        options.remoteImages = .block
        options.linkRoot = "/repo"
        return options
    }

    /// Every spelling a hostile document might try, under `mdv:` and at the top level.
    static let hostileSettings = """
        sanitize: false
        sanitizer: off
        remoteImages: keep
        remote_images: allow
        allowRemoteImages: true
        preprocessor: /bin/sh
        customPreprocessor: { executable: /usr/bin/touch, arguments: [/tmp/x] }
        builtInPreprocessors: [emoji]
        detectsFrontmatter: false
        appliesDocumentOverrides: false
        linkRoot: /
        headingAnchors: false
        highlighting: false
        sourceLines: false
        frontmatterDisplay: table
        gfmMarkup: cmark
        javascript: true
        contentSecurityPolicy: none
        """

    static let hostileBody = """
        # Title

        <script>alert(1)</script>
        <img src="https://evil.example/track.png" onerror="alert(2)">

        ![pixel](https://evil.example/pixel.png)

        [root](/docs/guide.md)

        ```swift
        let x = 1
        ```
        """

    static var hostileSource: String {
        let indented = hostileSettings.split(separator: "\n").map { "  \($0)" }.joined(separator: "\n")
        return "---\n\(hostileSettings)\nmdv:\n\(indented)\n  theme: serif\n---\n\(hostileBody)\n"
    }

    static func render(_ source: String = hostileSource) -> RenderedDocument {
        HTMLRenderer(options: viewerOptions).render(source)
    }

    @Test("every key besides flavor, theme, and wikilinks is reported as ignored")
    func reported() {
        let overrides = Self.render().overrides
        let keys = Self.hostileSettings.split(separator: "\n").map { "mdv." + $0.prefix { $0 != ":" } }
        #expect(overrides.ignored == keys.map { IgnoredOverride(key: $0, reason: .unknownKey) })
        #expect(overrides.theme == "serif", "the valid key beside them still applies")
    }

    @Test("sanitizing can't be turned off")
    func sanitizing() {
        let html = Self.render().html
        #expect(!html.contains("<script"))
        #expect(!html.contains("onerror"))
    }

    @Test("remote images stay blocked")
    func remoteImages() {
        let rendered = Self.render()
        #expect(rendered.blockedRemoteImages.count == 2)
        #expect(!rendered.html.contains("src=\"https://evil.example"))
    }

    @Test("viewer features and the link root stay as the caller set them")
    func features() {
        let rendered = Self.render()
        #expect(rendered.html.contains("data-source-line="), "source lines")
        #expect(rendered.html.contains("id=\"title\""), "heading anchors")
        #expect(rendered.html.contains("hljs-keyword"), "highlighting")
        #expect(rendered.html.contains("href=\"/repo/docs/guide.md\""), "linkRoot")
        #expect(!rendered.html.contains("frontmatter"), "frontmatter display")
    }

    @Test("the render matches the same document without the hostile keys")
    func sameAsWithout() {
        let clean = Self.render("---\nmdv:\n  theme: serif\n---\n\(Self.hostileBody)\n")
        let hostile = Self.render()
        // Line numbers differ (the hostile block is longer), so compare without them.
        let strip = { (html: String) in html.replacing(/\sdata-source-line="\d+"/, with: "") }
        #expect(strip(hostile.html) == strip(clean.html))
        #expect(hostile.blockedRemoteImages == clean.blockedRemoteImages)
    }

    @Test("applying any overrides changes nothing but the flavor")
    func applyingTouchesOnlyFlavor() {
        let options = Self.viewerOptions
        for overrides in [
            DocumentOverrides(flavor: "commonmark", theme: "serif", wikiLinks: false),
            DocumentOverrides(flavor: "spec"), DocumentOverrides(flavor: "../evil"),
            Self.render().overrides,
        ] {
            var expected = options
            if let id = overrides.flavor, FlavorRegistry.bundled.contains(id: id) {
                expected.flavor = FlavorRegistry.bundled.flavor(id: id)
            }
            #expect(options.applying(overrides) == expected, "\(overrides)")
        }
    }

    @Test("an unregistered flavor (spec, every extension) can't be chosen")
    func unregisteredFlavor() {
        let rendered = HTMLRenderer(options: RenderOptions(flavor: .commonmark))
            .render("---\nmdv: { flavor: spec }\n---\n~~x~~\n")
        #expect(!rendered.html.contains("<del>"))
        #expect(rendered.overrides.flavor == nil)
    }

    @Test("frontmatter can't run a preprocessor: nothing it names is executed")
    func noPreprocessor() async throws {
        let marker = FileManager.default.temporaryDirectory.appending(path: "mdv-override-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        let source = """
            ---
            mdv:
              preprocessor: /usr/bin/touch
              customPreprocessor: { executable: /usr/bin/touch, arguments: ["\(marker.path)"] }
            ---
            body
            """
        let rendered = try await HTMLRenderer(options: Self.viewerOptions).render(source, preprocessor: nil)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(rendered.overrides.ignored.map(\.reason) == [.unknownKey, .unknownKey])
        #expect(rendered.html.contains("body"))
    }

    @Test("top-level keys that look like settings are ordinary metadata, not overrides")
    func topLevel() {
        let rendered = Self.render("---\n\(Self.hostileSettings)\n---\n\(Self.hostileBody)\n")
        #expect(rendered.overrides == .none)
        #expect(!rendered.html.contains("<script"))
        #expect(rendered.blockedRemoteImages.count == 2)
    }
}
