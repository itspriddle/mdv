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
            (NSAppearance.Name.aqua, ThemeRegistry.bundled.defaultTheme.background.light),
            (NSAppearance.Name.darkAqua, ThemeRegistry.bundled.defaultTheme.background.dark),
        ])
    func themeBackground(appearance: NSAppearance.Name, expected: ThemeColor) throws {
        let color = try #require(
            try resolved(.themeBackground(ThemeRegistry.bundled.defaultTheme.background), in: appearance))
        #expect(Int((color.redComponent * 255).rounded()) == Int(expected.red))
        #expect(Int((color.greenComponent * 255).rounded()) == Int(expected.green))
        #expect(Int((color.blueComponent * 255).rounded()) == Int(expected.blue))
    }

    @Test("any theme's background resolves per appearance")
    func anyThemeBackground() throws {
        let background = ThemeBackground(light: ThemeColor(0xF0_E0_D0), dark: ThemeColor(0x10_20_30))
        for (name, expected) in [(NSAppearance.Name.aqua, background.light), (.darkAqua, background.dark)] {
            let color = try #require(try resolved(.themeBackground(background), in: name))
            #expect(Int((color.redComponent * 255).rounded()) == Int(expected.red), "\(name.rawValue)")
            #expect(Int((color.blueComponent * 255).rounded()) == Int(expected.blue), "\(name.rawValue)")
        }
    }

    @Test("document windows and web views paint the theme background before the page")
    func noWhiteFlash() throws {
        let controller = DocumentWindowController(themeSettings: ThemeSettings(isPersistent: false))
        let background = ThemeRegistry.bundled.defaultTheme.background
        let windowColor = try #require(controller.window?.backgroundColor)
        for (name, expected) in [(NSAppearance.Name.aqua, background.light), (.darkAqua, background.dark)] {
            let color = try #require(try resolved(windowColor, in: name))
            #expect(Self.matches(color, expected), "\(name.rawValue)")
        }
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
        let webView = DocumentWindowController(themeSettings: ThemeSettings(isPersistent: false)).coordinator
            .webView
        for name in sequence {
            webView.appearance = try #require(NSAppearance(named: name))
            #expect(webView.effectiveAppearance.name == name)
            var underPage: NSColor?
            webView.effectiveAppearance.performAsCurrentDrawingAppearance {
                underPage = webView.underPageBackgroundColor.usingColorSpace(.sRGB)
            }
            let color = try #require(underPage)
            let expected =
                name == .darkAqua
                ? ThemeRegistry.bundled.defaultTheme.background.dark
                : ThemeRegistry.bundled.defaultTheme.background.light
            #expect(Int((color.redComponent * 255).rounded()) == Int(expected.red), "\(name.rawValue)")
            #expect(Int((color.greenComponent * 255).rounded()) == Int(expected.green), "\(name.rawValue)")
            #expect(Int((color.blueComponent * 255).rounded()) == Int(expected.blue), "\(name.rawValue)")
        }
    }

    /// Whether `color` (sRGB) is `expected`, by value: windows make their own dynamic colors.
    static func matches(_ color: NSColor, _ expected: ThemeColor) -> Bool {
        Int((color.redComponent * 255).rounded()) == Int(expected.red)
            && Int((color.greenComponent * 255).rounded()) == Int(expected.green)
            && Int((color.blueComponent * 255).rounded()) == Int(expected.blue)
    }

    // MARK: View > Appearance

    /// View > Appearance's items, as built for the menu bar.
    static func appearanceItems() throws -> [NSMenuItem] {
        let view = try #require(MainMenu.build().item(withTitle: "View")?.submenu)
        let submenu = try #require(view.item(withTitle: "Appearance")?.submenu)
        return submenu.items
    }

    @Test("View > Appearance lists System, then Light and Dark, sent to the app delegate")
    func appearanceMenu() throws {
        let items = try Self.appearanceItems()
        #expect(items.map { $0.isSeparatorItem ? "-" : $0.title } == ["System", "-", "Light", "Dark"])
        for item in items where !item.isSeparatorItem {
            #expect(item.action == #selector(AppDelegate.chooseAppearance(_:)))
            #expect(item.target == nil)
        }
    }

    /// The action travels the responder chain, so nothing before the app delegate may answer it
    /// (`setAppearance:` would: it's the setter for `NSView.appearance` and `NSWindow.appearance`).
    @Test("View > Appearance reaches the app delegate through a document window's responder chain")
    func appearanceActionReachesDelegate() throws {
        let action = #selector(AppDelegate.chooseAppearance(_:))
        let controller = DocumentWindowController(themeSettings: ThemeSettings(isPersistent: false))
        let window = try #require(controller.window)
        var responder: NSResponder? = controller.coordinator.webView
        while let current = responder {
            #expect(!current.responds(to: action), "\(type(of: current)) answers \(action)")
            responder = current.nextResponder
        }
        #expect(!window.responds(to: action))
        #expect(!NSApplication.shared.responds(to: action))
        #expect(AppDelegate().responds(to: action))
    }

    @Test("View > Appearance sets the mode and checks the current one")
    func appearanceMenuAction() throws {
        let throwaway = try ThrowawayDefaults("mdv-appearance-tests")
        let settings = AppearanceSettings(defaults: throwaway.defaults, isPersistent: true)
        let delegate = AppDelegate(appearanceSettings: settings)
        let items = try Self.appearanceItems().filter { !$0.isSeparatorItem }
        let dark = try #require(items.first { $0.title == "Dark" })

        delegate.chooseAppearance(dark)
        #expect(settings.mode == .dark)
        for item in items {
            #expect(delegate.validateMenuItem(item))
            #expect(item.state == (item === dark ? .on : .off), "\(item.title)")
        }

        // A sender that isn't a mode item changes nothing.
        delegate.chooseAppearance(nil)
        #expect(settings.mode == .dark)
    }
}
