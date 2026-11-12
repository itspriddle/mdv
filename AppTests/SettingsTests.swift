import AppKit
import PeepCore
import Testing

@testable import PeepApp

/// The Settings window (#36): the model reads and writes the existing stores, follows changes
/// made elsewhere, and settings apply to windows (zoom and width live, theme and outline to new
/// windows). Everything runs over the suite's throwaway defaults and a fake Launch Services.
@MainActor
@Suite("Settings", .serialized, .timeLimit(.minutes(1)))
final class SettingsTests: DocumentWindowTestCase {
    let workspace = FakeWorkspace()

    func model(
        appearanceSettings: AppearanceSettings? = nil, themeSettings: ThemeSettings? = nil,
        zoomSettings: ZoomSettings? = nil,
        contentWidthSettings: ContentWidthSettings? = nil, markdownSettings: MarkdownSettings? = nil,
        openThemesFolder: (@MainActor () -> Void)? = nil
    ) -> SettingsModel {
        workspace.setHandler("com.example.other")
        let viewer = DefaultViewer(
            workspace: workspace, defaults: defaults, applicationURL: URL(filePath: "/Applications/Peep.app"),
            bundleIdentifier: "now.peep.Peep", isSuppressed: true)
        return SettingsModel(
            appearanceSettings: appearanceSettings ?? AppearanceSettings(defaults: defaults, isPersistent: true),
            themeSettings: themeSettings ?? self.themeSettings(),
            zoomSettings: zoomSettings ?? settings(),
            contentWidthSettings: contentWidthSettings ?? ContentWidthSettings(defaults: defaults, isPersistent: true),
            outlinePreference: OutlinePreference(defaults: defaults, isPersistent: true),
            markdownSettings: markdownSettings ?? MarkdownSettings(defaults: defaults, isPersistent: true),
            defaultViewerOffer: DefaultViewerOfferController(viewer: viewer), openThemesFolder: openThemesFolder)
    }

    // MARK: Model

    @Test("starts from the stores' values")
    func initialValues() {
        let model = model()
        #expect(model.appearanceMode == .system)
        #expect(model.themeSections.map { $0.map(\.id) } == [["github", "document", "serif"]])
        #expect(model.defaultThemeID == "github")
        #expect(model.zoomLevel == 1)
        #expect(model.contentWidth == .theme)
        #expect(!model.showsOutlineInNewWindows)
        #expect(!model.isDefaultViewer)
    }

    @Test("changes persist in the stores' defaults")
    func persists() {
        let model = model()
        model.setAppearanceMode(.dark)
        model.setDefaultTheme(id: "serif")
        model.setZoomLevel(1.25)
        model.setContentWidth(.wide)
        model.setShowsOutlineInNewWindows(true)

        #expect(defaults.string(forKey: AppearanceSettings.key) == "dark")
        #expect(defaults.string(forKey: ThemeSettings.defaultThemeKey) == "serif")
        #expect(defaults.double(forKey: ZoomSettings.key) == 1.25)
        #expect(defaults.string(forKey: ContentWidthSettings.key) == "wide")
        #expect(defaults.bool(forKey: OutlinePreference.key))

        // A fresh model over the same defaults (a relaunch) reads them back.
        let reread = self.model()
        #expect(reread.appearanceMode == .dark)
        #expect(reread.defaultThemeID == "serif")
        #expect(reread.zoomLevel == 1.25)
        #expect(reread.contentWidth == .wide)
        #expect(reread.showsOutlineInNewWindows)
    }

    @Test("an unregistered theme id is ignored; a deleted default shows the registry default")
    func unknownTheme() {
        let themes = themeSettings()
        let model = model(themeSettings: themes)
        model.setDefaultTheme(id: "nope")
        #expect(themes.defaultThemeID == nil)

        themes.defaultThemeID = "deleted-custom-theme"
        #expect(model.defaultThemeID == "github")
        // Showing the fallback doesn't overwrite the stored id (the theme may come back).
        #expect(themes.defaultThemeID == "deleted-custom-theme")
    }

    @Test("follows changes to the stores: defaults, custom themes")
    func followsStores() {
        let themes = themeSettings()
        let zoom = settings()
        let width = ContentWidthSettings(defaults: defaults, isPersistent: true)
        let model = model(themeSettings: themes, zoomSettings: zoom, contentWidthSettings: width)

        zoom.defaultLevel = 1.5
        width.defaultWidth = .narrow
        let custom = Theme(
            id: "custom:mine.css", displayName: "Mine", background: Theme.github.background, stylesheet: "")
        let failure = CustomThemeFailure(fileName: "broken.css", problem: .symbolicLink)
        themes.apply(CustomThemeCatalog(themes: [custom], failures: [failure]))

        #expect(model.zoomLevel == 1.5)
        #expect(model.contentWidth == .narrow)
        #expect(
            model.themeSections.map { $0.map(\.id) } == [["github", "document", "serif"], ["custom:mine.css"]])
        #expect(model.themeFailures == [failure.message])
        model.setDefaultTheme(id: "custom:mine.css")
        #expect(themes.defaultTheme == custom)

        themes.apply(.empty)
        #expect(model.themeFailures.isEmpty)
        // The custom default is kept while its file is gone; the picker shows the fallback.
        #expect(themes.defaultThemeID == "custom:mine.css")
        #expect(model.defaultThemeID == "github")
    }

    @Test("Open Themes Folder runs #35's action, and is hidden without custom themes")
    func themesFolder() {
        var opened = 0
        let model = model(openThemesFolder: { opened += 1 })
        #expect(model.canOpenThemesFolder)
        model.openThemesFolder()
        #expect(opened == 1)
        #expect(!self.model().canOpenThemesFolder)
    }

    @Test("appearance: System is the default and stores nothing; a bad stored value reads as System")
    func appearanceStore() {
        let appearance = AppearanceSettings(defaults: defaults, isPersistent: true)
        let model = model(appearanceSettings: appearance)
        model.setAppearanceMode(.light)
        #expect(defaults.string(forKey: AppearanceSettings.key) == "light")
        model.setAppearanceMode(.system)
        #expect(defaults.object(forKey: AppearanceSettings.key) == nil)

        defaults.set("sepia", forKey: AppearanceSettings.key)
        #expect(appearance.mode == .system)

        // Changes made elsewhere show in Settings.
        appearance.mode = .dark
        #expect(model.appearanceMode == .dark)
    }

    @Test("appearance: in memory under UI tests, never touching the defaults")
    func appearanceInMemory() {
        let appearance = AppearanceSettings(defaults: defaults, isPersistent: false)
        appearance.mode = .dark
        #expect(appearance.mode == .dark)
        #expect(defaults.object(forKey: AppearanceSettings.key) == nil)
    }

    @Test(
        "appearance applies its NSAppearance, System clears the override",
        arguments: [
            (AppearanceMode.light, NSAppearance.Name?.some(.aqua)),
            (.dark, .darkAqua),
            (.system, nil),
        ])
    func appearanceApplies(mode: AppearanceMode, expected: NSAppearance.Name?) {
        let appearance = AppearanceSettings(defaults: defaults, isPersistent: true)
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: .vibrantDark)
        appearance.mode = mode
        appearance.apply(to: window)
        #expect(window.appearance?.name == expected)
    }

    /// The page and the window background follow the window's effective appearance, which an
    /// app-level override (`NSApp.appearance`) sets for windows without their own.
    @Test("a dark override turns an open window's page dark")
    func appearanceAppliesToPage() async throws {
        defer { closeAll() }
        let (_, controller) = try await open()
        let window = try #require(controller.window)
        let appearance = AppearanceSettings(defaults: defaults, isPersistent: true)
        for (mode, scheme) in [(AppearanceMode.dark, "dark"), (.light, "light")] {
            appearance.mode = mode
            appearance.apply(to: window)
            try await until("prefers-color-scheme: \(scheme)") {
                let result = try await controller.coordinator.webView.callAsyncJavaScript(
                    "return matchMedia('(prefers-color-scheme: dark)').matches", arguments: [:], in: nil,
                    contentWorld: AppScripts.world)
                return (result as? Bool) == (mode == .dark)
            }
        }
    }

    @Test("zoom snaps to the nearest level and shows as a percentage")
    func zoomDisplay() {
        #expect(SettingsModel.nearestZoomLevel(to: 1.1000001) == 1.1)
        #expect(SettingsModel.nearestZoomLevel(to: 0.66) == 0.67)
        #expect(SettingsModel.zoomTitle(1.25) == "125%")
        #expect(SettingsModel.zoomTitle(0.67) == "67%")
    }

    @Test("Make Default makes Peep the default viewer")
    func defaultViewer() async {
        let model = model()
        #expect(!model.isDefaultViewer)
        await model.makeDefaultViewer()
        #expect(model.isDefaultViewer)
        #expect(!model.isMakingDefaultViewer)
        #expect(!workspace.setCalls.isEmpty)
    }

    // MARK: Windows

    @Test("zoom, width, and theme defaults apply to new windows only; the menus to one window")
    func appliesToNewWindows() async throws {
        defer { closeAll() }
        let themes = themeSettings()
        let zoom = settings()
        let width = ContentWidthSettings(defaults: defaults, isPersistent: true)
        let model = model(themeSettings: themes, zoomSettings: zoom, contentWidthSettings: width)
        let (_, open) = try await self.open(zoomSettings: zoom, contentWidthSettings: width, themeSettings: themes)

        model.setZoomLevel(1.5)
        model.setContentWidth(.narrow)
        model.setDefaultTheme(id: "serif")
        #expect(open.coordinator.webView.pageZoom == 1)
        #expect(open.coordinator.userStyle.contentWidth == .theme)
        #expect(open.theme == .github)

        let (_, new) = try await self.open(
            name: "new.md", zoomSettings: zoom, contentWidthSettings: width, themeSettings: themes)
        #expect(new.theme == .serif)
        #expect(new.zoomLevel == 1.5)
        #expect(new.coordinator.webView.pageZoom == 1.5)
        #expect(new.contentWidth == .narrow)
        #expect(new.coordinator.userStyle.contentWidth == .narrow)

        // A window's own changes leave Settings (and so later windows) alone.
        new.zoomInDocument(nil)
        new.setContentWidth(to: .full)
        #expect(model.zoomLevel == 1.5)
        #expect(model.contentWidth == .narrow)
        #expect(zoom.defaultLevel == 1.5)
        #expect(width.defaultWidth == .narrow)
    }

    @Test("the window: General and Markdown panes, titled like the window, not restorable")
    func window() throws {
        let controller = SettingsWindowController(model: model(), savesFrame: false)
        defer { controller.close() }
        let window = try #require(controller.window)
        #expect(window.identifier == SettingsWindowController.windowIdentifier)
        #expect(!window.isRestorable)
        let tabs = try #require(window.contentViewController as? NSTabViewController)
        #expect(tabs.tabStyle == .toolbar)
        #expect(tabs.tabViewItems.map(\.label) == ["General", "Markdown"])

        controller.show()
        #expect(window.isVisible)
        #expect(window.title == "General")
    }

    @Test("App menu > Settings… is Command-comma")
    func menuItem() throws {
        let item = try #require(MainMenu.build().items.first?.submenu?.item(withTitle: "Settings…"))
        #expect(item.action == #selector(AppDelegate.showSettings(_:)))
        #expect(item.keyEquivalent == ",")
        #expect(item.keyEquivalentModifierMask == .command)
    }
}
