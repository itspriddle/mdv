import AppKit
import MdvCore
import Testing
import WebKit

@testable import MdvApp

/// Content width (#37): the app-wide preset, windows following it live without a reload, the
/// menu, and the user layer over every bundled theme in real WebKit.
@MainActor
@Suite("Content width", .serialized, .timeLimit(.minutes(1)))
final class ContentWidthTests: DocumentWindowTestCase {
    /// 200 paragraphs long enough to wrap, so the width changes the page height.
    static let longSource = (1...200).map { "Paragraph \($0). " + String(repeating: "word ", count: 40) }
        .joined(separator: "\n\n")

    func widthSettings() -> ContentWidthSettings {
        ContentWidthSettings(defaults: defaults, isPersistent: true)
    }

    func evaluate(_ body: String, in coordinator: WebViewCoordinator) async throws -> Any? {
        try await coordinator.webView.callAsyncJavaScript(
            body, arguments: [:], in: nil, contentWorld: AppScripts.world)
    }

    /// The column's computed `max-width` (e.g. `512px`, `none`).
    func maxWidth(in coordinator: WebViewCoordinator) async throws -> String {
        try #require(
            try await evaluate(
                "return getComputedStyle(document.querySelector('article.markdown-body')).maxWidth;",
                in: coordinator) as? String)
    }

    /// `ems` (in `em`) in pixels of the column's own font size, as the computed `max-width` writes it.
    func pixels(_ ems: Double, in coordinator: WebViewCoordinator) async throws -> String {
        let fontSize = try #require(
            try await evaluate(
                "return parseFloat(getComputedStyle(document.querySelector('article.markdown-body')).fontSize);",
                in: coordinator) as? NSNumber)
        let value = ems * fontSize.doubleValue
        return value == value.rounded() ? "\(Int(value))px" : "\(value)px"
    }

    /// An item in View > Content Width.
    func widthItem(_ title: String) -> NSMenuItem? {
        MainMenu.build().item(withTitle: "View")?.submenu?.item(withTitle: "Content Width")?.submenu?
            .item(withTitle: title)
    }

    // MARK: Settings

    @Test("the preset persists, ignores bad stored values, and posts changes")
    func settingsPersist() {
        let settings = widthSettings()
        #expect(settings.width == .theme)
        var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: ContentWidthSettings.didChangeNotification, object: settings, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        settings.width = .narrow
        #expect(defaults.string(forKey: ContentWidthSettings.key) == "narrow")
        #expect(widthSettings().width == .narrow, "a new instance reads the persisted preset")
        settings.width = .narrow
        #expect(posts == 1, "setting the same preset posts nothing")
        settings.width = .theme
        #expect(defaults.object(forKey: ContentWidthSettings.key) == nil, "the default removes the key")
        defaults.set("100px; } body { display: none", forKey: ContentWidthSettings.key)
        #expect(settings.width == .theme)
        defaults.set(42, forKey: ContentWidthSettings.key)
        #expect(settings.width == .theme)
    }

    @Test("UI-test settings stay in memory")
    func settingsInMemory() {
        let settings = ContentWidthSettings(defaults: defaults, isPersistent: false)
        settings.width = .full
        #expect(settings.width == .full)
        #expect(defaults.object(forKey: ContentWidthSettings.key) == nil)
    }

    // MARK: Windows

    @Test("every window follows the preset live, keeping its reading position, and loads keep it")
    func windowsFollow() async throws {
        defer { closeAll() }
        let settings = widthSettings()
        let (_, first) = try await open(Self.longSource, contentWidthSettings: settings)
        let (_, second) = try await open(name: "other.md", contentWidthSettings: settings)
        let themeWidth = try await maxWidth(in: first.coordinator)
        #expect(themeWidth != "none")

        try await first.coordinator.scroll(toSourceLine: 201)
        let line = try await first.coordinator.currentSourceLine()
        let height = try #require(
            try await evaluate("return document.documentElement.scrollHeight;", in: first.coordinator) as? NSNumber)

        let narrow = try #require(widthItem("Narrow"))
        let narrowWidth = try await pixels(32, in: first.coordinator)
        first.setContentWidth(narrow)
        #expect(settings.width == .narrow)
        try await until("the first window narrows") { try await maxWidth(in: first.coordinator) == narrowWidth }
        try await until("the second window narrows") { try await maxWidth(in: second.coordinator) == narrowWidth }
        let narrowHeight = try #require(
            try await evaluate("return document.documentElement.scrollHeight;", in: first.coordinator) as? NSNumber)
        #expect(narrowHeight.doubleValue > height.doubleValue, "the column reflowed")
        #expect(abs(try await first.coordinator.currentSourceLine() - line) < 1, "the reading position is kept")

        settings.width = .full
        try await until("full width") { try await maxWidth(in: first.coordinator) == "none" }
        settings.width = .theme
        try await until("the theme's width") { try await maxWidth(in: first.coordinator) == themeWidth }

        // A new window and a full reload start with the current preset.
        settings.width = .wide
        let (document, third) = try await open(name: "third.md", contentWidthSettings: settings)
        #expect(try await maxWidth(in: third.coordinator) == (try await pixels(72, in: third.coordinator)))
        settings.width = .narrow
        try await third.coordinator.load(try #require(document.content).page, baseURL: nil)
        #expect(try await maxWidth(in: third.coordinator) == narrowWidth)
    }

    @Test("the current preset is checked in the menu")
    func validation() async throws {
        defer { closeAll() }
        let settings = widthSettings()
        let (_, controller) = try await open(contentWidthSettings: settings)
        let items = try ContentWidth.allCases.map { try #require(widthItem($0.displayName)) }
        for item in items {
            #expect(controller.validateMenuItem(item))
        }
        #expect(items.map(\.state) == [.off, .on, .off, .off])
        settings.width = .full
        _ = items.map(controller.validateMenuItem)
        #expect(items.map(\.state) == [.off, .off, .off, .on])
    }

    @Test("View > Content Width lists the presets")
    func menu() throws {
        let view = try #require(MainMenu.build().item(withTitle: "View")?.submenu)
        let submenu = try #require(view.item(withTitle: "Content Width")?.submenu)
        #expect(submenu.items.map(\.title) == ["Narrow", "Theme Default", "Wide", "Full Width"])
        #expect(submenu.items.allSatisfy { $0.action == #selector(DocumentWindowController.setContentWidth(_:)) })
        #expect(submenu.items.compactMap { $0.representedObject as? String } == ContentWidth.allCases.map(\.rawValue))
    }

    // MARK: Themes

    @Test("the user layer beats every bundled theme in light and dark", arguments: ThemeRegistry.bundled.themes)
    func everyTheme(theme: Theme) async throws {
        let coordinator = WebViewCoordinator()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 600), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.webView
        defer { window.close() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            coordinator.webView.appearance = NSAppearance(named: appearance)
            for (width, ems) in [(ContentWidth.narrow, 32.0), (.wide, 72), (.full, nil)] {
                let html = HTMLDocument(
                    title: "t", body: "<p>text</p>", theme: theme, userStyle: UserStyle(contentWidth: width),
                    contentSecurityPolicy: .viewer
                ).html
                try await coordinator.load(html: html, baseURL: nil)
                let expected = if let ems { try await pixels(ems, in: coordinator) } else { "none" }
                #expect(try await maxWidth(in: coordinator) == expected, "\(theme.id) \(appearance.rawValue)")
            }
        }
    }
}
