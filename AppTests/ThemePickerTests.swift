import AppKit
import MdvCore
import Testing

@testable import MdvApp

/// The theme picker (#34): per-window themes, the in-place switch, menus, restoration, and
/// registry changes (custom themes, #35).
@MainActor
@Suite("Theme picker", .serialized, .timeLimit(.minutes(1)))
final class ThemePickerTests: DocumentWindowTestCase {
    /// A document taller than the window: 200 one-line paragraphs.
    static let longSource = (1...200).map { "Paragraph \($0) about themes." }.joined(separator: "\n\n")

    /// Opens `longSource` (or `source`) with `themeSettings`, once the page has loaded.
    func openLong(
        _ source: String = longSource, name: String = "themes.md", themeSettings: ThemeSettings
    ) async throws -> (MarkdownDocument, DocumentWindowController) {
        try await open(source, name: name, zoomSettings: nil, themeSettings: themeSettings)
    }

    func evaluate(_ script: String, in controller: DocumentWindowController) async throws -> Any? {
        try await controller.coordinator.webView.callAsyncJavaScript(
            script, arguments: [:], in: nil, contentWorld: AppScripts.world)
    }

    func pageThemeCSS(in controller: DocumentWindowController) async throws -> String? {
        // The page's own element has a newline either side of the CSS; a swap sets the CSS alone.
        (try await evaluate("return document.getElementById('mdv-theme').textContent;", in: controller) as? String)?
            .trimmingCharacters(in: .newlines)
    }

    func fontFamily(in controller: DocumentWindowController) async throws -> String? {
        try await evaluate(
            "return getComputedStyle(document.querySelector('.markdown-body')).fontFamily;", in: controller) as? String
    }

    func windowBackgroundMatches(_ controller: DocumentWindowController, _ theme: Theme) throws -> Bool {
        let color = try #require(controller.window?.backgroundColor)
        var matches = true
        for (name, expected) in [(NSAppearance.Name.aqua, theme.background.light), (.darkAqua, theme.background.dark)] {
            let appearance = try #require(NSAppearance(named: name))
            var resolved: NSColor?
            appearance.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) }
            let sRGB = try #require(resolved)
            matches = matches && AppearanceTests.matches(sRGB, expected)
        }
        return matches
    }

    // MARK: Settings

    @Test("the default theme persists, falls back for unknown ids, and posts changes")
    func settingsPersist() {
        let settings = themeSettings()
        #expect(settings.defaultTheme == ThemeRegistry.bundled.defaultTheme)
        var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: ThemeSettings.didChangeNotification, object: settings, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        settings.defaultThemeID = "serif"
        settings.defaultThemeID = "serif"
        #expect(posts == 1)
        #expect(defaults.string(forKey: ThemeSettings.defaultThemeKey) == "serif")
        #expect(themeSettings().defaultTheme == .serif, "a new instance reads the persisted id")
        settings.defaultThemeID = "deleted-custom-theme"
        #expect(settings.defaultTheme == ThemeRegistry.bundled.defaultTheme)

        let memory = ThemeSettings(defaults: defaults, isPersistent: false)
        memory.defaultThemeID = "document"
        #expect(memory.defaultTheme == .document)
        #expect(defaults.string(forKey: ThemeSettings.defaultThemeKey) == "deleted-custom-theme")
    }

    // MARK: Switching

    @Test("switching swaps the stylesheet in place, keeping the page, position, find, and zoom")
    func switchesInPlace() async throws {
        defer { closeAll() }
        let (_, controller) = try await openLong(themeSettings: themeSettings())
        let coordinator = controller.coordinator
        #expect(try await pageThemeCSS(in: controller) == Theme.github.layerCSS.trimmingCharacters(in: .newlines))

        try await coordinator.scroll(toSourceLine: 201)
        coordinator.find.show()
        coordinator.find.setQuery("Paragraph 1")
        await coordinator.find.waitUntilIdle()
        let matches = coordinator.find.matchCount
        #expect(matches > 1)
        coordinator.webView.pageZoom = 1.25
        // A marker in the app world's globals: a reload would start a fresh page without it.
        _ = try await evaluate("window.mdvThemeTestMarker = 42; return true;", in: controller)
        let line = try await coordinator.currentSourceLine()

        let familyBefore = try await fontFamily(in: controller)
        controller.setTheme(id: "serif")
        #expect(controller.theme == .serif)
        #expect(try windowBackgroundMatches(controller, .serif))
        await coordinator.pendingThemeSwap?.value
        #expect(try await pageThemeCSS(in: controller) == Theme.serif.layerCSS.trimmingCharacters(in: .newlines))
        let family = try await fontFamily(in: controller)
        #expect(family != familyBefore, "the computed style changed: \(family ?? "nil")")

        #expect(try await evaluate("return window.mdvThemeTestMarker;", in: controller) as? Int == 42, "no reload")
        #expect(abs(try await coordinator.currentSourceLine() - line) < 1, "reading position kept")
        #expect(coordinator.find.matchCount == matches)
        #expect(try await evaluate("return CSS.highlights.size;", in: controller) as? Int ?? 0 > 0, "highlights kept")
        #expect(coordinator.webView.pageZoom == 1.25)
    }

    @Test("a theme picked while the page loads ends up in the page")
    func switchDuringLoad() async throws {
        defer { closeAll() }
        let settings = themeSettings()
        let file = folder.appending(path: "loading.md")
        try Data(Self.longSource.utf8).write(to: file)
        let document = try MarkdownDocument(contentsOf: file, ofType: Self.markdownType)
        let controller = DocumentWindowController(zoomSettings: self.settings(), themeSettings: settings)
        document.addWindowController(controller)
        documents.append(document)
        controller.setTheme(id: "document")
        try await until("the first load") { controller.coordinator.hasLoadedPage }
        try await until("the theme swap") {
            try await pageThemeCSS(in: controller) == Theme.document.layerCSS.trimmingCharacters(in: .newlines)
        }
        #expect(controller.coordinator.loadedTheme == .document)
    }

    @Test("a live reload keeps the window's theme, and a full reload uses it")
    func reloadKeepsTheme() async throws {
        defer { closeAll() }
        let (document, controller) = try await openLong(themeSettings: themeSettings())
        controller.setTheme(id: "serif")
        await controller.coordinator.pendingThemeSwap?.value
        let content = try #require(document.content)
        document.setContent(
            DocumentContent(source: content.source + "\n\nAppended.", fallbackTitle: "themes.md"))
        try await until("the live reload") {
            try await evaluate("return document.body.textContent.includes('Appended.');", in: controller) as? Bool
                == true
        }
        #expect(try await pageThemeCSS(in: controller) == Theme.serif.layerCSS.trimmingCharacters(in: .newlines))
        try await controller.coordinator.load(content.page, baseURL: nil)
        #expect(try await pageThemeCSS(in: controller) == Theme.serif.layerCSS.trimmingCharacters(in: .newlines))
    }

    @Test("each window has its own theme; a pick doesn't change the default for new windows")
    func perWindow() async throws {
        defer { closeAll() }
        let settings = themeSettings()
        let (_, first) = try await openLong(themeSettings: settings)
        let (_, second) = try await openLong(name: "second.md", themeSettings: settings)
        let item = NSMenuItem("Serif", action: #selector(DocumentWindowController.selectTheme(_:)))
        item.representedObject = "serif"
        first.selectTheme(item)
        #expect(first.theme == .serif)
        #expect(second.theme == .github)
        #expect(settings.defaultThemeID == nil)
        let (_, third) = try await openLong(name: "third.md", themeSettings: settings)
        #expect(third.theme == .github)

        // The default (Settings) applies to new windows only.
        settings.defaultThemeID = "serif"
        #expect(first.theme == .serif)
        #expect(second.theme == .github)
        let (_, fourth) = try await openLong(name: "fourth.md", themeSettings: settings)
        #expect(fourth.theme == .serif)
        #expect(try await pageThemeCSS(in: fourth) == Theme.serif.layerCSS.trimmingCharacters(in: .newlines))
        #expect(try windowBackgroundMatches(fourth, .serif))

        // An item for an id that isn't registered does nothing.
        item.representedObject = "nope"
        first.selectTheme(item)
        #expect(first.theme == .serif)
    }

    // MARK: Menus

    @Test("View > Theme lists the registered themes and checks the window's")
    func menu() async throws {
        defer { closeAll() }
        let view = try #require(MainMenu.build().item(withTitle: "View")?.submenu)
        let submenu = try #require(view.item(withTitle: "Theme")?.submenu)
        // The themes, then Open Themes Folder (#35) after a separator.
        let themeItems = Array(submenu.items.dropLast(2))
        #expect(submenu.items.suffix(2).map(\.title) == ["", "Open Themes Folder"])
        #expect(themeItems.map(\.title) == ThemeRegistry.bundled.themes.map(\.displayName))
        #expect(themeItems.map { $0.representedObject as? String } == ThemeRegistry.bundled.themes.map(\.id))
        #expect(themeItems.allSatisfy { $0.action == #selector(DocumentWindowController.selectTheme(_:)) })

        let (_, controller) = try await openLong(themeSettings: themeSettings())
        controller.setTheme(id: "document")
        for item in themeItems {
            #expect(controller.validateMenuItem(item))
            #expect(item.state == (item.representedObject as? String == "document" ? .on : .off), "\(item.title)")
        }
    }

    @Test("the theme menu adds custom themes in their own section when it opens")
    func menuFollowsRegistry() {
        let settings = themeSettings()
        let menu = ThemeMenu.makeMenu(settings: settings)
        let custom = Theme(id: "custom:mine", displayName: "Mine", background: Theme.github.background, stylesheet: "")
        settings.registry = ThemeRegistry.bundled.adding([custom])
        menu.delegate?.menuNeedsUpdate?(menu)
        #expect(menu.items.count == ThemeRegistry.bundled.themes.count + 2)
        #expect(menu.items.dropLast().last?.isSeparatorItem == true)
        #expect(menu.items.last?.title == "Mine")
    }

    // MARK: Restoration and registry changes

    @Test("window restoration keeps the theme; unknown or bad ids show the default")
    func restoration() async throws {
        defer { closeAll() }
        let settings = themeSettings()
        let (_, controller) = try await openLong(themeSettings: settings)
        controller.setTheme(id: "serif")
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        controller.encodeThemeState(with: archiver)
        archiver.finishEncoding()

        let (_, restored) = try await openLong(name: "restored.md", themeSettings: settings)
        restored.restoreThemeState(with: try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData))
        #expect(restored.theme == .serif)
        await restored.coordinator.pendingThemeSwap?.value
        #expect(try await pageThemeCSS(in: restored) == Theme.serif.layerCSS.trimmingCharacters(in: .newlines))

        let badValues: [Any] = ["deleted-custom-theme", 42, String(repeating: "x", count: 1000)]
        for (index, bad) in badValues.enumerated() {
            let (_, window) = try await openLong(name: "bad-\(index).md", themeSettings: settings)
            let state = NSKeyedArchiver(requiringSecureCoding: true)
            state.encode(bad, forKey: DocumentWindowController.themeStateKey)
            state.finishEncoding()
            window.restoreThemeState(with: try NSKeyedUnarchiver(forReadingFrom: state.encodedData))
            #expect(window.theme == ThemeRegistry.bundled.defaultTheme, "\(bad)")
        }
    }

    @Test("a removed custom theme falls back to the default, and an edited one is swapped in")
    func registryChanges() async throws {
        defer { closeAll() }
        let custom = Theme(
            id: "custom:mine", displayName: "Mine", background: Theme.serif.background,
            stylesheet: ".markdown-body { letter-spacing: 1px; }")
        let settings = themeSettings(registry: ThemeRegistry.bundled.adding([custom]))
        let (_, controller) = try await openLong(themeSettings: settings)
        controller.setTheme(id: custom.id)
        await controller.coordinator.pendingThemeSwap?.value
        #expect(try await pageThemeCSS(in: controller) == custom.layerCSS.trimmingCharacters(in: .newlines))

        var edited = custom
        edited.stylesheet = ".markdown-body { letter-spacing: 2px; }"
        settings.registry = ThemeRegistry.bundled.adding([edited])
        await controller.coordinator.pendingThemeSwap?.value
        #expect(try await pageThemeCSS(in: controller) == edited.layerCSS.trimmingCharacters(in: .newlines))

        settings.registry = .bundled
        #expect(controller.theme == ThemeRegistry.bundled.defaultTheme)
        await controller.coordinator.pendingThemeSwap?.value
        #expect(
            try await pageThemeCSS(in: controller)
                == ThemeRegistry.bundled.defaultTheme.layerCSS.trimmingCharacters(in: .newlines))
        #expect(try windowBackgroundMatches(controller, ThemeRegistry.bundled.defaultTheme))
        #expect(controller.themeID == custom.id, "the pick is kept in case the theme comes back")

        settings.registry = ThemeRegistry.bundled.adding([edited])
        #expect(controller.theme == edited)
    }
}
