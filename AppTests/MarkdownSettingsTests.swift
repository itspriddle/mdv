import AppKit
import MdvCore
import Testing

@testable import MdvApp

/// Settings > Markdown (#55): the store persists and distrusts stored values, the model follows
/// it, and open documents render again in place (no reload, reading position kept) when a
/// setting changes. Everything runs over the suite's throwaway defaults.
@MainActor
@Suite("Markdown settings", .serialized, .timeLimit(.minutes(1)))
final class MarkdownSettingsTests: DocumentWindowTestCase {
    /// A table (GFM only), then enough paragraphs to scroll.
    static let longSource =
        "| a | b |\n| - | - |\n| 1 | 2 |\n\n"
        + (1...200).map { "Paragraph \($0). " + String(repeating: "word ", count: 30) }.joined(separator: "\n\n")

    func store() -> MarkdownSettings {
        MarkdownSettings(defaults: defaults, isPersistent: true)
    }

    func model(markdownSettings: MarkdownSettings) -> SettingsModel {
        let viewer = DefaultViewer(
            workspace: FakeWorkspace(), defaults: defaults, applicationURL: URL(filePath: "/Applications/mdv.app"),
            bundleIdentifier: "com.itspriddle.mdv", isSuppressed: true)
        return SettingsModel(
            appearanceSettings: AppearanceSettings(defaults: defaults, isPersistent: true),
            themeSettings: themeSettings(), zoomSettings: settings(),
            contentWidthSettings: ContentWidthSettings(defaults: defaults, isPersistent: true),
            outlinePreference: OutlinePreference(defaults: defaults, isPersistent: true),
            markdownSettings: markdownSettings, defaultViewerOffer: DefaultViewerOfferController(viewer: viewer))
    }

    func evaluate(_ body: String, in controller: DocumentWindowController) async throws -> Any? {
        try await controller.coordinator.webView.callAsyncJavaScript(
            body, arguments: [:], in: nil, contentWorld: AppScripts.world)
    }

    func pageHas(_ selector: String, in controller: DocumentWindowController) async throws -> Bool {
        try await evaluate("return document.querySelector('.markdown-body \(selector)') !== null;", in: controller)
            as? Bool ?? false
    }

    // MARK: Store

    @Test("defaults: GFM, frontmatter hidden, no preprocessors; nothing stored")
    func defaultValues() {
        let store = store()
        #expect(store.defaultFlavorID == "gfm")
        #expect(store.frontmatterDisplay == .hidden)
        #expect(store.builtInPreprocessors.isEmpty)
        #expect(store.preferences == .default)
        #expect(defaults.object(forKey: MarkdownSettings.flavorKey) == nil)
    }

    @Test("changes persist, post one notification each, and the default stores nothing")
    func persists() {
        let store = store()
        let posts = PostCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: MarkdownSettings.didChangeNotification, object: store, queue: .main
        ) { _ in MainActor.assumeIsolated { posts.count += 1 } }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.defaultFlavorID = "commonmark"
        store.frontmatterDisplay = .table
        store.defaultFlavorID = "commonmark"  // unchanged: no post
        #expect(posts.count == 2)
        #expect(defaults.string(forKey: MarkdownSettings.flavorKey) == "commonmark")
        #expect(defaults.string(forKey: MarkdownSettings.frontmatterKey) == "table")

        // A relaunch reads them back.
        let reread = self.store()
        #expect(reread.defaultFlavor == .commonmark)
        #expect(reread.frontmatterDisplay == .table)
        #expect(reread.preferences == MarkdownPreferences(flavor: .commonmark, frontmatterDisplay: .table))

        store.defaultFlavorID = "gfm"
        store.frontmatterDisplay = .hidden
        #expect(defaults.object(forKey: MarkdownSettings.flavorKey) == nil)
        #expect(defaults.object(forKey: MarkdownSettings.frontmatterKey) == nil)
    }

    @Test("stored values are untrusted: unknown ids read as defaults, unknown flavors aren't set")
    func untrusted() {
        let store = store()
        defaults.set("markdown-extra", forKey: MarkdownSettings.flavorKey)
        defaults.set("sidebar", forKey: MarkdownSettings.frontmatterKey)
        defaults.set(["emoji", "nope"], forKey: MarkdownSettings.preprocessorsKey)
        #expect(store.defaultFlavor == .gfm)
        #expect(store.frontmatterDisplay == .hidden)
        // Flavor-owned transforms (emoji) are never a built-in preprocessor.
        #expect(store.builtInPreprocessors.isEmpty)

        defaults.removeObject(forKey: MarkdownSettings.flavorKey)
        store.defaultFlavorID = "nope"
        #expect(defaults.object(forKey: MarkdownSettings.flavorKey) == nil)
        store.builtInPreprocessors = [.emojiShortcodes]
        #expect(store.builtInPreprocessors.isEmpty)
        defaults.set(["emoji", "wikiLinks", "nope"], forKey: MarkdownSettings.preprocessorsKey)
        #expect(store.builtInPreprocessors == [.wikiLinks])
    }

    @Test("wiki links are the one built-in preprocessor offered; turning them on persists")
    func wikiLinksPersist() {
        #expect(MarkdownSettings.optionalPreprocessors == [.wikiLinks])
        let store = store()
        store.builtInPreprocessors = [.wikiLinks, .alerts]
        #expect(store.builtInPreprocessors == [.wikiLinks])
        #expect(defaults.stringArray(forKey: MarkdownSettings.preprocessorsKey) == ["wikiLinks"])
        #expect(self.store().preferences.builtInPreprocessors == [.wikiLinks])
        #expect(DocumentContent.renderOptions(preferences: store.preferences).builtInPreprocessors == [.wikiLinks])
        store.builtInPreprocessors = []
        #expect(defaults.object(forKey: MarkdownSettings.preprocessorsKey) == nil)
    }

    @Test("in memory under UI tests, never touching the defaults")
    func inMemory() {
        let store = MarkdownSettings(defaults: defaults, isPersistent: false)
        store.defaultFlavorID = "commonmark"
        store.frontmatterDisplay = .table
        #expect(store.preferences == MarkdownPreferences(flavor: .commonmark, frontmatterDisplay: .table))
        #expect(defaults.object(forKey: MarkdownSettings.flavorKey) == nil)
        #expect(defaults.object(forKey: MarkdownSettings.frontmatterKey) == nil)
    }

    @Test("preferences apply to render options; the default flavor stays overridable in MdvCore")
    func applies() {
        let preferences = MarkdownPreferences(flavor: .commonmark, frontmatterDisplay: .table)
        let options = DocumentContent.renderOptions(preferences: preferences)
        #expect(options.flavor == .commonmark)
        #expect(options.frontmatterDisplay == .table)
        #expect(options.builtInPreprocessors.isEmpty)
        #expect(options.sourceLines)
    }

    // MARK: Model

    @Test("the model lists the registry's flavors and follows the store")
    func model() {
        let store = store()
        let model = model(markdownSettings: store)
        #expect(model.flavors.map(\.id) == ["gfm", "commonmark"])
        #expect(model.defaultFlavorID == "gfm")
        #expect(model.frontmatterDisplay == .hidden)
        #expect(model.optionalPreprocessors == MarkdownSettings.optionalPreprocessors)

        model.setDefaultFlavor(id: "commonmark")
        model.setFrontmatterDisplay(.table)
        #expect(store.defaultFlavor == .commonmark)
        #expect(store.frontmatterDisplay == .table)

        store.defaultFlavorID = "gfm"
        #expect(model.defaultFlavorID == "gfm")
        model.setDefaultFlavor(id: "nope")
        #expect(model.defaultFlavorID == "gfm")
        model.setBuiltInPreprocessor(.emojiShortcodes, isOn: true)
        #expect(model.builtInPreprocessors.isEmpty)
        model.setBuiltInPreprocessor(.wikiLinks, isOn: true)
        #expect(model.builtInPreprocessors == [.wikiLinks])
        #expect(store.builtInPreprocessors == [.wikiLinks])
        model.setBuiltInPreprocessor(.wikiLinks, isOn: false)
        #expect(store.builtInPreprocessors.isEmpty)
    }

    // MARK: Open documents

    @Test("changing the flavor re-renders open documents in place, keeping the reading position")
    func flavorAppliesInPlace() async throws {
        defer { closeAll() }
        let store = store()
        let (document, controller) = try await open(Self.longSource, markdownSettings: store)
        let coordinator = controller.coordinator
        #expect(try await pageHas("table", in: controller))

        try await coordinator.scroll(toSourceLine: 201)
        let line = try await coordinator.currentSourceLine()
        // A marker in the app world's globals: a reload would start a fresh page without it.
        _ = try await evaluate("window.mdvMarkdownSettingsMarker = 42; return true;", in: controller)

        store.defaultFlavorID = "commonmark"
        try await until("the CommonMark render") { try await !pageHas("table", in: controller) }
        #expect(document.content?.preferences.flavor == .commonmark)
        #expect(
            try await evaluate("return window.mdvMarkdownSettingsMarker;", in: controller) as? Int == 42, "no reload")
        #expect(abs(try await coordinator.currentSourceLine() - line) < 1, "reading position kept")

        store.defaultFlavorID = "gfm"
        try await until("the GFM render") { try await pageHas("table", in: controller) }
    }

    @Test("showing frontmatter adds the table to open documents; Copy as HTML copies what shows")
    func frontmatterApplies() async throws {
        defer { closeAll() }
        let store = store()
        let source = "---\ntitle: Notes\ntags: [a, b]\n---\n\n| a |\n| - |\n| 1 |\n"
        let (_, controller) = try await open(source, markdownSettings: store)
        #expect(try await !pageHas("table.frontmatter", in: controller))

        store.frontmatterDisplay = .table
        try await until("the frontmatter table") { try await pageHas("table.frontmatter", in: controller) }

        store.defaultFlavorID = "commonmark"
        try await until("the CommonMark render") { try await !pageHas("table:not(.frontmatter)", in: controller) }
        await controller.writeHTML(to: pasteboard)
        let html = try #require(pasteboard.string(forType: .html))
        #expect(html.contains("<table class=\"frontmatter\">"))
        #expect(html.contains("| a |"), "the body is CommonMark")
    }

    @Test("content rendered with older settings (a reload in flight) is rendered again")
    func staleContentRendersAgain() async throws {
        defer { closeAll() }
        let store = store()
        let (document, controller) = try await open(Self.longSource, markdownSettings: store)
        store.defaultFlavorID = "commonmark"
        try await until("the CommonMark render") { try await !pageHas("table", in: controller) }

        // A live reload that read the file before the change lands with GFM.
        let content = try #require(document.content)
        document.setContent(DocumentContent(source: content.source + "\n\nAppended.", fallbackTitle: "notes.md"))
        try await until("the re-render") { document.content?.preferences.flavor == .commonmark }
        try await until("the appended text") {
            try await evaluate("return document.body.textContent.includes('Appended.');", in: controller) as? Bool
                ?? false
        }
        #expect(try await !pageHas("table", in: controller))
    }

    @Test("a document opened after the change renders with it")
    func newDocuments() async throws {
        defer { closeAll() }
        let store = store()
        store.defaultFlavorID = "commonmark"
        let (document, controller) = try await open(Self.longSource, markdownSettings: store)
        try await until("the CommonMark render") { document.content?.preferences.flavor == .commonmark }
        try await until("no table") { try await !pageHas("table", in: controller) }
    }
}

/// Counts notifications (posted on the main thread).
@MainActor
private final class PostCounter {
    var count = 0
}
