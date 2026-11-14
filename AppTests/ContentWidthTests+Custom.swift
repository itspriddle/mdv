import AppKit
import PeepCore
import Testing

@testable import PeepApp

/// Settings' custom content width: one px width that, while on, every window uses instead of
/// its preset.
extension ContentWidthTests {
    // MARK: Settings

    @Test("the custom width persists, reads bad stored values as defaults, clamps, and posts changes")
    func customSettingsPersist() {
        let settings = widthSettings()
        #expect(!settings.isCustomWidthEnabled)
        #expect(settings.customWidthPoints == CustomContentWidth.defaultPoints)
        #expect(settings.customWidth == nil, "off by default")
        var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: ContentWidthSettings.didChangeNotification, object: settings, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        settings.customWidthPoints = 640
        #expect(settings.customWidth == nil, "a width alone doesn't turn it on")
        settings.isCustomWidthEnabled = true
        #expect(settings.customWidth == CustomContentWidth(points: 640))
        #expect(defaults.integer(forKey: ContentWidthSettings.customPointsKey) == 640)
        #expect(defaults.bool(forKey: ContentWidthSettings.customEnabledKey))
        #expect(widthSettings().customWidth == CustomContentWidth(points: 640), "a new instance reads it")
        settings.isCustomWidthEnabled = true
        settings.customWidthPoints = 640
        #expect(posts == 2, "setting the same values posts nothing")

        settings.customWidthPoints = 10
        #expect(settings.customWidthPoints == CustomContentWidth.range.lowerBound)
        settings.customWidthPoints = 100_000
        #expect(settings.customWidthPoints == CustomContentWidth.range.upperBound)
        settings.customWidthPoints = CustomContentWidth.defaultPoints
        #expect(defaults.object(forKey: ContentWidthSettings.customPointsKey) == nil, "the default removes the key")
        settings.isCustomWidthEnabled = false
        #expect(defaults.object(forKey: ContentWidthSettings.customEnabledKey) == nil, "off removes the key")

        for bad: Any in [5, 99_999, "800px; } body { display: none", 12.5] {
            defaults.set(bad, forKey: ContentWidthSettings.customPointsKey)
            #expect(settings.customWidthPoints == CustomContentWidth.defaultPoints, "\(bad)")
        }
        defaults.set("yes", forKey: ContentWidthSettings.customEnabledKey)
        #expect(!settings.isCustomWidthEnabled)
    }

    @Test("UI-test custom width settings stay in memory")
    func customSettingsInMemory() {
        let settings = ContentWidthSettings(defaults: defaults, isPersistent: false)
        settings.isCustomWidthEnabled = true
        settings.customWidthPoints = 700
        #expect(settings.customWidth == CustomContentWidth(points: 700))
        #expect(defaults.object(forKey: ContentWidthSettings.customEnabledKey) == nil)
        #expect(defaults.object(forKey: ContentWidthSettings.customPointsKey) == nil)
    }

    // MARK: Windows

    @Test("the custom width overrides every window live, keeping each window's preset for later")
    func customOverridesWindows() async throws {
        defer { closeAll() }
        let settings = widthSettings()
        let (_, first) = try await open(Self.longSource, contentWidthSettings: settings)
        let (_, second) = try await open(name: "other.md", contentWidthSettings: settings)
        first.setContentWidth(to: .full)
        let themeWidth = try await maxWidth(in: second.coordinator)
        try await until("full width") { try await maxWidth(in: first.coordinator) == "none" }
        try await first.coordinator.scroll(toSourceLine: 201)
        let line = try await first.coordinator.currentSourceLine()

        settings.customWidthPoints = 640
        settings.isCustomWidthEnabled = true
        for controller in [first, second] {
            try await until("the custom width") { try await maxWidth(in: controller.coordinator) == "640px" }
            let sizing =
                try await evaluate(
                    "return getComputedStyle(document.querySelector('article.markdown-body')).boxSizing;",
                    in: controller.coordinator) as? String
            #expect(sizing == "content-box", "the width is the text's")
        }
        #expect(abs(try await first.coordinator.currentSourceLine() - line) < 1, "the reading position is kept")
        #expect(first.contentWidth == .full, "the window keeps its preset")

        settings.customWidthPoints = 900
        try await until("the new custom width") { try await maxWidth(in: first.coordinator) == "900px" }

        let (_, third) = try await open(name: "third.md", contentWidthSettings: settings)
        #expect(try await maxWidth(in: third.coordinator) == "900px", "new windows start with it")

        settings.isCustomWidthEnabled = false
        try await until("the first window's preset") { try await maxWidth(in: first.coordinator) == "none" }
        try await until("the second window's preset") {
            try await maxWidth(in: second.coordinator) == themeWidth
        }
    }

    @Test("with the custom width on, the menu checks it and disables the presets")
    func customValidation() async throws {
        defer { closeAll() }
        let settings = widthSettings()
        let (_, controller) = try await open(contentWidthSettings: settings)
        let submenu = try #require(
            MainMenu.build().item(withTitle: "View")?.submenu?.item(withTitle: "Content Width")?.submenu)
        let custom = try #require(
            submenu.items.first {
                $0.representedObject as? String == DocumentWindowController.customContentWidthItemValue
            })
        let separator = try #require(submenu.items.first { $0.isSeparatorItem })
        let presets = submenu.items.filter { $0.representedObject is String && $0 !== custom }

        #expect(!controller.validateMenuItem(custom))
        #expect(custom.isHidden && separator.isHidden, "hidden while off")
        #expect(presets.map(controller.validateMenuItem) == [true, true, true, true])

        settings.customWidthPoints = 720
        settings.isCustomWidthEnabled = true
        #expect(!controller.validateMenuItem(custom))
        #expect(!custom.isHidden && !separator.isHidden)
        #expect(custom.title == "Custom: 720px")
        #expect(custom.state == .on)
        #expect(presets.map(controller.validateMenuItem) == [false, false, false, false])
        #expect(presets.allSatisfy { $0.state == .off })

        controller.setContentWidth(custom)
        #expect(controller.contentWidth == .theme, "the custom item changes nothing")
    }

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
}
