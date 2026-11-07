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
        #expect(controller.coordinator.webView.isHidden)
    }

    /// WebKit on macOS 26 keeps `underPageBackgroundColor` resolved for the appearance it was set
    /// in, so the web view re-resolves it on each change. The color is read as the web view
    /// draws it: resolved in the web view's own appearance.
    @Test(
        "the web view's under-page background follows appearance changes",
        arguments: [
            [NSAppearance.Name.darkAqua, .aqua],
            [.aqua, .darkAqua],
        ])
    func underPageBackgroundFollowsAppearance(sequence: [NSAppearance.Name]) throws {
        let webView = DocumentWindowController().coordinator.webView
        for name in sequence {
            webView.appearance = try #require(NSAppearance(named: name))
            #expect(webView.effectiveAppearance.name == name)
            var underPage: NSColor?
            webView.effectiveAppearance.performAsCurrentDrawingAppearance {
                underPage = webView.underPageBackgroundColor.usingColorSpace(.sRGB)
            }
            let color = try #require(underPage)
            let expected = name == .darkAqua ? DefaultTheme.background.dark : DefaultTheme.background.light
            #expect(Int((color.redComponent * 255).rounded()) == Int(expected.red), "\(name.rawValue)")
            #expect(Int((color.greenComponent * 255).rounded()) == Int(expected.green), "\(name.rawValue)")
            #expect(Int((color.blueComponent * 255).rounded()) == Int(expected.blue), "\(name.rawValue)")
        }
    }
}
