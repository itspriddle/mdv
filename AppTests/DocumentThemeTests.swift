import AppKit
import Foundation
import PeepCore
import Testing

@testable import PeepApp

/// Frontmatter overrides in the app (#54): a document's `peep.theme` against the reader's pick and
/// Settings' default, View > Theme > Document's Theme, live reload, and restoration.
@MainActor
@Suite("Document theme", .serialized, .timeLimit(.minutes(1)))
final class DocumentThemeTests: DocumentWindowTestCase {
    static func source(theme: String?, flavor: String? = nil, body: String = "# Themed\n\nSome text.\n") -> String {
        let settings = [theme.map { "theme: \"\($0)\"" }, flavor.map { "flavor: \($0)" }].compactMap(\.self)
        guard !settings.isEmpty else {
            return body
        }
        return "---\ntitle: Themed\npeep:\n" + settings.map { "  \($0)\n" }.joined() + "---\n" + body
    }

    func openThemed(
        _ theme: String?, name: String = "themed.md", flavor: String? = nil, themeSettings: ThemeSettings
    ) async throws -> (MarkdownDocument, DocumentWindowController) {
        try await open(Self.source(theme: theme, flavor: flavor), name: name, themeSettings: themeSettings)
    }

    func evaluate(_ script: String, in controller: DocumentWindowController) async throws -> Any? {
        try await controller.coordinator.webView.callAsyncJavaScript(
            script, arguments: [:], in: nil, contentWorld: AppScripts.world)
    }

    func pageShows(_ theme: Theme, in controller: DocumentWindowController) async throws -> Bool {
        let css = try await evaluate("return document.getElementById('peep-theme').textContent;", in: controller)
        return (css as? String)?.trimmingCharacters(in: .newlines) == theme.layerCSS.trimmingCharacters(in: .newlines)
    }

    func documentThemeItem() -> NSMenuItem {
        ThemeMenu.documentThemeItem()
    }

    // MARK: Precedence

    @Test("a document opens in its frontmatter theme, which beats Settings' default")
    func opensInDocumentTheme() async throws {
        defer { closeAll() }
        let settings = themeSettings()
        settings.defaultThemeID = "document"
        let (_, controller) = try await openThemed("serif", themeSettings: settings)
        #expect(controller.theme == .serif)
        #expect(controller.pickedThemeID == nil)
        #expect(controller.documentThemeID == "serif")
        #expect(try await pageShows(.serif, in: controller))
        #expect(controller.coordinator.loadedTheme == .serif, "the first load used it, no swap needed")

        let (_, plain) = try await openThemed(nil, name: "plain.md", themeSettings: settings)
        #expect(plain.theme == .document, "without one, Settings' default")
    }

    @Test("the reader's pick beats the frontmatter; Document's Theme goes back to it")
    func pickBeatsDocument() async throws {
        defer { closeAll() }
        let (_, controller) = try await openThemed("serif", themeSettings: themeSettings())
        let item = documentThemeItem()
        #expect(!controller.validateMenuItem(item), "nothing to go back to while following the document")
        #expect(item.title == "Document's Theme (Serif)")

        let pick = NSMenuItem("GitHub", action: #selector(DocumentWindowController.selectTheme(_:)))
        pick.representedObject = "github"
        controller.selectTheme(pick)
        #expect(controller.theme == .github)
        #expect(controller.validateMenuItem(pick) && pick.state == .on)
        await controller.coordinator.pendingThemeSwap?.value
        #expect(try await pageShows(.github, in: controller))
        #expect(controller.validateMenuItem(item))

        controller.useDocumentTheme(item)
        #expect(controller.pickedThemeID == nil)
        #expect(controller.theme == .serif)
        await controller.coordinator.pendingThemeSwap?.value
        #expect(try await pageShows(.serif, in: controller))
    }

    @Test("Document's Theme is disabled for a document without a theme")
    func noDocumentTheme() async throws {
        defer { closeAll() }
        let (_, controller) = try await openThemed(nil, themeSettings: themeSettings())
        controller.setTheme(id: "serif")
        let item = documentThemeItem()
        #expect(!controller.validateMenuItem(item))
        #expect(item.title == "Document's Theme")
    }

    @Test("View > Theme starts with Document's Theme")
    func menu() throws {
        let view = try #require(MainMenu.build().item(withTitle: "View")?.submenu)
        let submenu = try #require(view.item(withTitle: "Theme")?.submenu)
        #expect(submenu.items.first?.title == "Document's Theme")
        #expect(submenu.items.first?.action == #selector(DocumentWindowController.useDocumentTheme(_:)))
        #expect(submenu.items.dropFirst().first?.isSeparatorItem == true)
    }

    @Test("an unknown frontmatter theme shows Settings' default; a custom one appears when it loads")
    func fallback() async throws {
        defer { closeAll() }
        let settings = themeSettings()
        settings.defaultThemeID = "document"
        let (_, unknown) = try await openThemed("no-such-theme", themeSettings: settings)
        #expect(unknown.theme == .document)

        let (_, controller) = try await openThemed("custom:later.css", name: "custom.md", themeSettings: settings)
        #expect(controller.theme == .document)
        let later = Theme(
            id: "custom:later.css", displayName: "Later", background: Theme.serif.background,
            stylesheet: ".markdown-body { letter-spacing: 1px; }")
        settings.registry = ThemeRegistry.bundled.adding([later])
        #expect(controller.theme == later)
        await controller.coordinator.pendingThemeSwap?.value
        #expect(try await pageShows(later, in: controller))
    }

    @Test("each window of a document resolves its own pick over the shared document theme")
    func perWindow() async throws {
        defer { closeAll() }
        let settings = themeSettings()
        let (document, first) = try await openThemed("serif", themeSettings: settings)
        let second = DocumentWindowController(zoomSettings: self.settings(), themeSettings: settings)
        document.addWindowController(second)
        try await until("the second window's load") { second.coordinator.hasLoadedPage }
        first.setTheme(id: "document")
        #expect(first.theme == .document)
        #expect(second.theme == .serif)
    }

    // MARK: Live reload

    @Test("editing peep.theme swaps the theme in place; removing it goes back to the default")
    func liveReloadTheme() async throws {
        defer { closeAll() }
        let settings = themeSettings()
        let (document, controller) = try await openThemed("serif", themeSettings: settings)
        let file = try #require(document.fileURL)
        document.startLiveReload()
        // A marker in the app world's globals: a reload would start a fresh page without it.
        _ = try await evaluate("window.peepDocumentThemeMarker = 7; return true;", in: controller)

        try Data(Self.source(theme: "document").utf8).write(to: file, options: .atomic)
        try await until("the theme from the edited file") { controller.theme == .document }
        try await until("the page swap") { try await pageShows(.document, in: controller) }
        #expect(try await evaluate("return window.peepDocumentThemeMarker;", in: controller) as? Int == 7, "no reload")

        try Data(Self.source(theme: nil).utf8).write(to: file, options: .atomic)
        try await until("the default theme") { controller.theme == ThemeRegistry.bundled.defaultTheme }
        #expect(controller.documentThemeID == nil)
    }

    @Test("a live reload never overrides the reader's pick")
    func liveReloadKeepsPick() async throws {
        defer { closeAll() }
        let (document, controller) = try await openThemed("serif", themeSettings: themeSettings())
        let file = try #require(document.fileURL)
        document.startLiveReload()
        controller.setTheme(id: "github")
        try Data(Self.source(theme: "document", body: "# Edited\n").utf8).write(to: file, options: .atomic)
        try await until("the reload") { controller.documentThemeID == "document" }
        #expect(controller.theme == .github)
    }

    @Test("editing peep.flavor re-renders with the new flavor")
    func liveReloadFlavor() async throws {
        defer { closeAll() }
        let table = "| a | b |\n| - | - |\n| 1 | 2 |\n"
        let (document, controller) = try await open(
            Self.source(theme: nil, flavor: "gfm", body: table), name: "flavor.md", themeSettings: themeSettings())
        let file = try #require(document.fileURL)
        document.startLiveReload()
        let hasTable = { try await self.evaluate("return document.querySelector('table') !== null;", in: controller) }
        #expect(try await hasTable() as? Bool == true)
        try Data(Self.source(theme: nil, flavor: "commonmark", body: table).utf8).write(to: file, options: .atomic)
        try await until("the CommonMark render") { try await hasTable() as? Bool == false }
    }

    // MARK: Restoration

    @Test("restoration saves only the reader's pick, so the frontmatter applies again on relaunch")
    func restoration() async throws {
        defer { closeAll() }
        let settings = themeSettings()
        let (_, following) = try await openThemed("serif", themeSettings: settings)
        let unpicked = NSKeyedArchiver(requiringSecureCoding: true)
        following.encodeThemeState(with: unpicked)
        unpicked.finishEncoding()
        let decoder = try NSKeyedUnarchiver(forReadingFrom: unpicked.encodedData)
        #expect(!decoder.containsValue(forKey: DocumentWindowController.themeStateKey))

        // The file's theme changed while the app was closed: the restored window shows the new one.
        let (_, relaunched) = try await openThemed("document", name: "relaunched.md", themeSettings: settings)
        relaunched.restoreThemeState(with: decoder)
        #expect(relaunched.theme == .document)
        #expect(relaunched.pickedThemeID == nil)

        following.setTheme(id: "github")
        let picked = NSKeyedArchiver(requiringSecureCoding: true)
        following.encodeThemeState(with: picked)
        picked.finishEncoding()
        let (_, restored) = try await openThemed("serif", name: "restored.md", themeSettings: settings)
        restored.restoreThemeState(with: try NSKeyedUnarchiver(forReadingFrom: picked.encodedData))
        #expect(restored.theme == .github, "a restored pick beats the frontmatter")
    }

    @Test("a pick restored before the first render still beats the frontmatter")
    func restoredBeforeRender() async throws {
        defer { closeAll() }
        let settings = themeSettings()
        let state = NSKeyedArchiver(requiringSecureCoding: true)
        state.encode("github" as NSString, forKey: DocumentWindowController.themeStateKey)
        state.finishEncoding()

        let file = folder.appending(path: "early.md")
        try Data(Self.source(theme: "serif").utf8).write(to: file)
        let document = try MarkdownDocument(contentsOf: file, ofType: Self.markdownType)
        let controller = DocumentWindowController(zoomSettings: self.settings(), themeSettings: settings)
        controller.restoreThemeState(with: try NSKeyedUnarchiver(forReadingFrom: state.encodedData))
        document.addWindowController(controller)
        documents.append(document)
        try await until("the first load") { controller.coordinator.hasLoadedPage }
        #expect(controller.documentThemeID == "serif")
        #expect(controller.theme == .github)
        #expect(try await pageShows(.github, in: controller))
    }
}
