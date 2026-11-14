import AppKit
import PeepCore
import SwiftUI
import Testing

@testable import PeepApp

/// The window's chrome blends with its theme: the titlebar shows the theme background, the
/// border and status bar use its colors, and the title stays legible on a background whose
/// darkness doesn't match the system appearance.
@MainActor
@Suite("Window chrome", .serialized, .timeLimit(.minutes(1)))
final class WindowChromeTests: DocumentWindowTestCase {
    /// A custom-style theme with one dark background in both appearances.
    static let midnight = Theme(
        id: "midnight", displayName: "Midnight",
        background: ThemeBackground(light: ThemeColor(0x10_14_20), dark: ThemeColor(0x10_14_20)), stylesheet: "")

    func resolved(_ color: NSColor?, in name: NSAppearance.Name) -> NSColor? {
        var result: NSColor?
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            result = color?.usingColorSpace(.sRGB)
        }
        return result
    }

    @Test("the titlebar is transparent over the theme background, without the system separator")
    func titlebar() async throws {
        defer { closeAll() }
        let (_, controller) = try await open()
        let window = try #require(controller.window)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titlebarSeparatorStyle == .none)
        let background = Theme.github.background
        #expect(resolved(window.backgroundColor, in: .aqua) == NSColor(background.light).usingColorSpace(.sRGB))
        #expect(resolved(window.backgroundColor, in: .darkAqua) == NSColor(background.dark).usingColorSpace(.sRGB))
        #expect(controller.chrome.background == background)
    }

    @Test("switching themes recolors the chrome")
    func themeSwitch() async throws {
        defer { closeAll() }
        let (_, controller) = try await open()
        controller.setTheme(id: Theme.serif.id)
        #expect(controller.chrome.background == Theme.serif.background)
        let window = try #require(controller.window)
        for (name, color) in [
            (NSAppearance.Name.aqua, Theme.serif.background.light), (.darkAqua, Theme.serif.background.dark),
        ] {
            let expected = NSColor(color).usingColorSpace(.sRGB)
            #expect(resolved(window.backgroundColor, in: name) == expected, "titlebar, \(name.rawValue)")
            #expect(
                resolved(controller.outlineController.chromeView.backgroundColor, in: name) == expected,
                "sidebar, \(name.rawValue)")
            #expect(
                resolved(controller.outlineController.chromeView.borderColor, in: name)
                    == NSColor(color.chromeBorder).usingColorSpace(.sRGB), "sidebar edge, \(name.rawValue)")
        }
    }

    @Test("a theme from the document's frontmatter colors the chrome")
    func documentTheme() async throws {
        defer { closeAll() }
        let (_, controller) = try await open("---\npeep:\n  theme: serif\n---\n# Title\n")
        #expect(controller.chrome.background == Theme.serif.background)
        let window = try #require(controller.window)
        #expect(
            resolved(window.backgroundColor, in: .darkAqua)
                == NSColor(Theme.serif.background.dark).usingColorSpace(.sRGB))
        #expect(
            resolved(controller.outlineController.chromeView.backgroundColor, in: .darkAqua)
                == NSColor(Theme.serif.background.dark).usingColorSpace(.sRGB))
    }

    @Test("a dark background in Light mode forces a dark titlebar and keeps the page light")
    func mismatchedBackground() async throws {
        defer { closeAll() }
        let settings = themeSettings(registry: ThemeRegistry.bundled.adding([Self.midnight]))
        let (_, controller) = try await open(themeSettings: settings, appearance: .aqua)
        let window = try #require(controller.window)
        #expect(controller.forcedAppearance == nil)

        controller.setTheme(id: Self.midnight.id)
        #expect(window.appearance?.name == .darkAqua)
        #expect(window.contentView?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
        #expect(
            controller.coordinator.webView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
        #expect(
            window.backgroundColor.usingColorSpace(.sRGB)
                == NSColor(Self.midnight.background.light).usingColorSpace(.sRGB))

        #expect(controller.outlineController.view.appearance?.name == .darkAqua, "the sidebar is chrome")

        controller.setTheme(id: Theme.github.id)
        #expect(window.appearance?.name == .aqua, "the window's own appearance comes back")
        #expect(window.contentView?.appearance == nil)
        #expect(controller.outlineController.view.appearance == nil)
        #expect(controller.forcedAppearance == nil)
    }

    @Test("status bar colors follow the system appearance; its contents contrast with the background")
    func statusBarColors() {
        let chrome = WindowChrome(background: Theme.github.background)
        let light = chrome.colors(in: .light)
        #expect(light.background == Theme.github.background.light)
        #expect(light.border == Theme.github.background.light.chromeBorder)
        #expect(light.contentScheme == .light)
        #expect(chrome.colors(in: .dark).contentScheme == .dark)

        chrome.background = Self.midnight.background
        #expect(chrome.colors(in: .light).contentScheme == .dark)
    }
}
