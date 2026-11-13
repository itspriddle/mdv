import AppKit
import PeepCore
import Testing

@testable import PeepApp

/// The shipped app carries every third-party notice and shows it in the About panel (#85).
@MainActor
@Suite("About panel")
struct AboutPanelTests {
    @Test("the bundle ships every notice, and the credits show each one")
    func bundledCredits() throws {
        let root = try #require(Bundle.main.resourceURL)
        let acknowledgements = try Acknowledgements(root: root)
        #expect(acknowledgements.components.count >= 8)
        let credits = try #require(AboutPanel.credits()).string
        let creditWords = credits.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for component in acknowledgements.components {
            #expect(credits.contains(component.name))
            let license = try Acknowledgements.licenseText(of: component, root: root)
            let words = license.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            #expect(creditWords.contains(words), "\(component.name)'s license isn't in the credits")
        }
    }

    @Test("links each component's name to its homepage, and colors follow the appearance")
    func attributes() throws {
        let component = Acknowledgement(
            name: "Example", use: "Testing", homepage: "https://example.com", license: "MIT",
            licenseFile: "Example.LICENSE", licenseSource: "https://example.com/LICENSE")
        let credits = AboutPanel.credits(for: [component], licenses: ["Copyright (c) Example\nline two\n"])
        let range = (credits.string as NSString).range(of: "Example")
        #expect(
            credits.attribute(.link, at: range.location, effectiveRange: nil) as? URL
                == URL(string: "https://example.com"))
        #expect(credits.string.contains("Copyright (c) Example line two"))
        credits.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: credits.length)) { color, _, _ in
            #expect([NSColor.labelColor, .secondaryLabelColor].contains(color as? NSColor))
        }
    }

    @Test("App menu > About Peep shows Peep's About panel")
    func menuItem() throws {
        let appMenu = try #require(NSApp.mainMenu?.items.first?.submenu)
        #expect(appMenu.items.first?.action == #selector(AppDelegate.showAboutPanel(_:)))
    }
}
