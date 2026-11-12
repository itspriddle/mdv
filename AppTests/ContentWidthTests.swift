import AppKit
import PeepCore
import Testing
import WebKit

@testable import PeepApp

/// Content width (#37, per window since #47): the default for new windows, each window's own
/// preset applied live without a reload, restoration, the menu, and the user layer over every
/// bundled theme in real WebKit.
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

    /// `ems` (in `em`) in pixels of the column's own font size.
    func pixels(_ ems: Double, in coordinator: WebViewCoordinator) async throws -> Double {
        let fontSize = try #require(
            try await evaluate(
                "return parseFloat(getComputedStyle(document.querySelector('article.markdown-body')).fontSize);",
                in: coordinator) as? NSNumber)
        return ems * fontSize.doubleValue
    }

    /// Whether a computed `max-width` is `pixels`, allowing for WebKit's rounding of fractional px.
    func isWidth(_ computed: String, is pixels: Double) -> Bool {
        guard computed.hasSuffix("px"), let value = Double(computed.dropLast(2)) else { return false }
        return abs(value - pixels) < 0.01
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
        #expect(settings.defaultWidth == .theme)
        var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: ContentWidthSettings.didChangeNotification, object: settings, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        settings.defaultWidth = .narrow
        #expect(defaults.string(forKey: ContentWidthSettings.key) == "narrow")
        #expect(widthSettings().defaultWidth == .narrow, "a new instance reads the persisted preset")
        settings.defaultWidth = .narrow
        #expect(posts == 1, "setting the same preset posts nothing")
        settings.defaultWidth = .theme
        #expect(defaults.object(forKey: ContentWidthSettings.key) == nil, "the default removes the key")
        defaults.set("100px; } body { display: none", forKey: ContentWidthSettings.key)
        #expect(settings.defaultWidth == .theme)
        defaults.set(42, forKey: ContentWidthSettings.key)
        #expect(settings.defaultWidth == .theme)
    }

    @Test("UI-test settings stay in memory")
    func settingsInMemory() {
        let settings = ContentWidthSettings(defaults: defaults, isPersistent: false)
        settings.defaultWidth = .full
        #expect(settings.defaultWidth == .full)
        #expect(defaults.object(forKey: ContentWidthSettings.key) == nil)
    }

    // MARK: Windows

    @Test("a preset changes only its window, live, keeping its reading position; loads keep it")
    func windowsAreIndependent() async throws {
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
        #expect(first.contentWidth == .narrow)
        #expect(settings.defaultWidth == .theme, "the default for new windows is Settings'")
        try await until("the first window narrows") {
            isWidth(try await maxWidth(in: first.coordinator), is: narrowWidth)
        }
        let narrowHeight = try #require(
            try await evaluate("return document.documentElement.scrollHeight;", in: first.coordinator) as? NSNumber)
        #expect(narrowHeight.doubleValue > height.doubleValue, "the column reflowed")
        #expect(abs(try await first.coordinator.currentSourceLine() - line) < 1, "the reading position is kept")
        #expect(second.contentWidth == .theme)
        #expect(try await maxWidth(in: second.coordinator) == themeWidth, "the other window keeps its width")

        first.setContentWidth(to: .full)
        try await until("full width") { try await maxWidth(in: first.coordinator) == "none" }
        first.setContentWidth(to: .theme)
        try await until("the theme's width") { try await maxWidth(in: first.coordinator) == themeWidth }

        // A new window starts with Settings' default; a full reload keeps the window's preset.
        settings.defaultWidth = .wide
        #expect(first.contentWidth == .theme, "a new default leaves open windows alone")
        let (document, third) = try await open(name: "third.md", contentWidthSettings: settings)
        #expect(third.contentWidth == .wide)
        #expect(isWidth(try await maxWidth(in: third.coordinator), is: try await pixels(72, in: third.coordinator)))
        third.setContentWidth(to: .narrow)
        try await third.coordinator.load(try #require(document.content).page, baseURL: nil)
        #expect(isWidth(try await maxWidth(in: third.coordinator), is: narrowWidth))
    }

    @Test("the window's preset is checked in the menu")
    func validation() async throws {
        defer { closeAll() }
        let settings = widthSettings()
        let (_, controller) = try await open(contentWidthSettings: settings)
        let items = try ContentWidth.allCases.map { try #require(widthItem($0.displayName)) }
        for item in items {
            #expect(controller.validateMenuItem(item))
        }
        #expect(items.map(\.state) == [.off, .on, .off, .off])
        controller.setContentWidth(to: .full)
        _ = items.map(controller.validateMenuItem)
        #expect(items.map(\.state) == [.off, .off, .off, .on])
        settings.defaultWidth = .narrow
        _ = items.map(controller.validateMenuItem)
        #expect(items.map(\.state) == [.off, .off, .off, .on], "Settings' default doesn't change the window")
    }

    @Test("window restoration keeps the preset and ignores bad values")
    func restoration() async throws {
        defer { closeAll() }
        let settings = widthSettings()
        let (_, controller) = try await open(contentWidthSettings: settings)
        controller.setContentWidth(to: .wide)
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        controller.encodeContentWidthState(with: archiver)
        archiver.finishEncoding()

        settings.defaultWidth = .narrow
        let (_, restored) = try await open(name: "restored.md", contentWidthSettings: settings)
        #expect(restored.contentWidth == .narrow)
        restored.restoreContentWidthState(with: try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData))
        #expect(restored.contentWidth == .wide)
        #expect(restored.coordinator.userStyle.contentWidth == .wide)

        // Untrusted values (not a preset, not a string) and state saved before #47 (no key)
        // leave the window at Settings' default.
        for value: Any? in ["100px; } body { display: none", 42, nil] {
            let bad = NSKeyedArchiver(requiringSecureCoding: true)
            if let value {
                bad.encode(value, forKey: DocumentWindowController.contentWidthStateKey)
            }
            bad.finishEncoding()
            let (_, window) = try await open(name: "bad.md", contentWidthSettings: settings)
            window.restoreContentWidthState(with: try NSKeyedUnarchiver(forReadingFrom: bad.encodedData))
            #expect(window.contentWidth == .narrow, "\(String(describing: value))")
        }
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
                let actual = try await maxWidth(in: coordinator)
                let label = "\(theme.id) \(appearance.rawValue) \(width.rawValue): \(actual)"
                if let ems {
                    let expected = try await pixels(ems, in: coordinator)
                    #expect(isWidth(actual, is: expected), "\(label), expected \(expected)px")
                } else {
                    #expect(actual == "none", "\(label)")
                }
            }
        }
    }
}
