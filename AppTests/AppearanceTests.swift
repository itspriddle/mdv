import AppKit
import MdvCore
import Testing

@testable import MdvApp

@MainActor
@Suite("Appearance")
struct AppearanceTests {
    func resolved(_ color: NSColor, in name: NSAppearance.Name) throws -> NSColor? {
        let appearance = try #require(NSAppearance(named: name))
        var result: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB)
        }
        return result
    }

    @Test(
        "the window background is the theme's, per appearance",
        arguments: [
            (NSAppearance.Name.aqua, DefaultTheme.background.light),
            (NSAppearance.Name.darkAqua, DefaultTheme.background.dark),
        ])
    func themeBackground(appearance: NSAppearance.Name, expected: ThemeColor) throws {
        let color = try #require(try resolved(.themeBackground, in: appearance))
        #expect(Int((color.redComponent * 255).rounded()) == Int(expected.red))
        #expect(Int((color.greenComponent * 255).rounded()) == Int(expected.green))
        #expect(Int((color.blueComponent * 255).rounded()) == Int(expected.blue))
    }

    @Test("document windows and web views paint the theme background before the page")
    func noWhiteFlash() throws {
        let controller = DocumentWindowController()
        #expect(controller.window?.backgroundColor == .themeBackground)
        let underPage = try #require(
            try resolved(controller.coordinator.webView.underPageBackgroundColor, in: .darkAqua))
        #expect(Int((underPage.redComponent * 255).rounded()) == Int(DefaultTheme.background.dark.red))
        #expect(controller.coordinator.webView.isHidden)
    }
}
