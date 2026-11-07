import AppKit
import Foundation
import MdvCore
import Testing

@testable import MdvApp

/// A window whose custom theme is missing or broken (#45): it shows Settings' default theme,
/// GitHub only when that default is missing too, and keeps its pick for when the file returns.
extension CustomThemeLibraryTests {
    @Test("a window whose custom theme is deleted or broken shows Settings' default theme, and its pick when back")
    func fallbackToSettingsDefault() async throws {
        defer { closeAll() }
        let settings = themeSettings()
        settings.defaultThemeID = Theme.serif.id
        let mine = Theme(
            id: "custom:mine.css", displayName: "Mine", background: Theme.github.background, stylesheet: "")
        settings.apply(CustomThemeCatalog(themes: [mine]))
        let (_, controller) = try await open(themeSettings: settings)
        controller.setTheme(id: mine.id)
        #expect(controller.theme == mine)

        // Deleted: Settings' default, not GitHub.
        settings.apply(.empty)
        #expect(controller.theme == Theme.serif)
        await controller.coordinator.pendingThemeSwap?.value
        #expect(
            try await pageThemeCSS(in: controller) == Theme.serif.layerCSS.trimmingCharacters(in: .newlines))

        // Settings' default changes while the window falls back: the window follows it.
        settings.defaultThemeID = Theme.document.id
        #expect(controller.theme == Theme.document)

        // Broken (a failure, not registered): the same fallback.
        settings.apply(CustomThemeCatalog(failures: [CustomThemeFailure(fileName: "mine.css", problem: .notUTF8)]))
        #expect(controller.theme == Theme.document)

        // Settings' default is itself a missing custom theme: GitHub, the registry's default.
        settings.defaultThemeID = "custom:gone.css"
        #expect(controller.theme == ThemeRegistry.bundled.defaultTheme)

        // Back: the window kept its pick.
        settings.apply(CustomThemeCatalog(themes: [mine]))
        #expect(controller.theme == mine)
        #expect(controller.themeID == mine.id)
    }

    @Test("a window showing a registered theme ignores Settings' default")
    func registeredThemeIgnoresDefault() async throws {
        defer { closeAll() }
        let settings = themeSettings()
        let (_, controller) = try await open(themeSettings: settings)
        controller.setTheme(id: Theme.serif.id)
        settings.defaultThemeID = Theme.document.id
        #expect(controller.theme == Theme.serif)
    }
}
