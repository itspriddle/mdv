import AppKit
import MdvCore
import PDFKit
import Testing
import WebKit

@testable import MdvApp

/// Print themes (#38) in real WebKit: each bundled theme printed to PDF (the Save as PDF path)
/// from a light and a dark window, then read back. Paper is the same from both appearances,
/// light, with the theme's fonts at a paper text size, code unclipped and its fills kept, and a
/// `<picture>`'s light image. The CSS itself is covered by MdvCore's `PrintThemeTests`.
@MainActor
@Suite("Print themes", .serialized, .timeLimit(.minutes(2)))
final class PrintThemeTests: DocumentWindowTestCase {
    static let longLine = (1...30).map { "printed\($0)" }.joined(separator: "_")

    static let document = """
        # Print Theme

        Body text for the paper size check, with `inline code` and a [relative link](other.md).

        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="dark.svg">
          <img src="light.svg" alt="logo">
        </picture>

        ```
        \(longLine)
        ```

        ```diff
        - removed line
        + added line
        ```

        | Name | Value |
        | ---- | ----- |
        | one  | 1     |
        """

    /// A solid-color SVG, so the image's pixels are easy to find on the printed page.
    static func svg(_ color: String) -> Data {
        Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="240" height="120">\
            <rect width="240" height="120" fill="\(color)"/></svg>
            """.utf8)
    }

    struct Printed {
        let pdf: PDFDocument
        let page: PDFPage
        let raster: PrintedPage
    }

    /// Opens the test document in `themeID` in a window with `appearance` from the start, and
    /// prints it to PDF.
    func print(
        themeID: String, appearance: NSAppearance.Name, registry: ThemeRegistry = .bundled
    ) async throws -> (Printed, DocumentWindowController) {
        try Self.svg("#ff0000").write(to: folder.appending(path: "light.svg"))
        try Self.svg("#0000ff").write(to: folder.appending(path: "dark.svg"))
        let settings = themeSettings(registry: registry)
        settings.defaultThemeID = themeID
        let (document, controller) = try await open(
            Self.document, name: "\(themeID)-\(appearance.rawValue).md", themeSettings: settings,
            appearance: appearance)
        #expect(controller.theme.id == themeID)
        _ = try await controller.coordinator.webView.callAsyncJavaScript(
            "await Promise.all(Array.from(document.images).map((img) => img.decode().catch(() => null)));",
            arguments: [:], in: nil, contentWorld: AppScripts.world)
        let isDark = appearance == .darkAqua
        #expect(try await showsDarkPicture(controller) == isDark, "the screen shows the \(appearance.rawValue) image")
        let pdf = try await printToPDF(document, in: controller, named: "\(themeID)-\(appearance.rawValue).pdf")
        let page = try #require(pdf.page(at: 0))
        #expect(try await showsDarkPicture(controller) == isDark, "printing doesn't change the screen's image")
        return (Printed(pdf: pdf, page: page, raster: try PrintedPage(page)), controller)
    }

    /// Whether the window's page currently shows the dark `<picture>` source.
    func showsDarkPicture(_ controller: DocumentWindowController) async throws -> Bool {
        let source = try await controller.coordinator.webView.callAsyncJavaScript(
            "return document.querySelector('picture img').currentSrc;", arguments: [:], in: nil,
            contentWorld: AppScripts.world)
        return (source as? String)?.hasSuffix("/dark.svg") == true
    }

    /// The light-appearance computed background of the first element matching `selector`, as
    /// 0...255 sRGB components.
    func lightBackground(of selector: String, in controller: DocumentWindowController) async throws -> [Int] {
        let value = try await controller.coordinator.webView.callAsyncJavaScript(
            """
            const color = getComputedStyle(document.querySelector(selector)).backgroundColor;
            return color.match(/\\d+(\\.\\d+)?/g).slice(0, 3).map(Number);
            """, arguments: ["selector": selector], in: nil, contentWorld: AppScripts.world)
        return try #require(value as? [NSNumber]).map { Int($0.doubleValue.rounded()) }
    }

    @Test(
        "each theme prints light, themed, and the same from a dark window", arguments: ["github", "document", "serif"])
    func printsThemedAndLight(themeID: String) async throws {
        defer { closeAll() }
        let (light, lightController) = try await print(themeID: themeID, appearance: .aqua)
        let codeFill = try await lightBackground(of: "pre", in: lightController)
        let (dark, _) = try await print(themeID: themeID, appearance: .darkAqua)

        for (name, printed) in [("light", light), ("dark", dark)] {
            let bounds = printed.page.bounds(for: .mediaBox)
            #expect(printed.pdf.pageCount == 1, "\(name)")
            #expect((500...700).contains(bounds.width) && bounds.height > bounds.width, "\(name): page \(bounds)")

            // Paper is light: mostly white, with only text-sized dark marks.
            let raster = printed.raster
            #expect(raster.meanLightness > 0.85, "\(name): mean lightness \(raster.meanLightness)")
            let darkPixels = raster.fraction { max($0, $1, $2) < 90 }
            #expect(darkPixels < 0.05, "\(name): dark pixels \(darkPixels)")
            // The picture prints its light image, never the dark one.
            #expect(raster.fraction { $0 > 220 && $1 < 40 && $2 < 40 } > 0.01, "\(name): the light image prints")
            #expect(raster.fraction { $0 < 40 && $1 < 40 && $2 > 220 } == 0, "\(name): the dark image never prints")
            // Code blocks keep the theme's light fill.
            let fill = raster.fraction {
                abs($0 - codeFill[0]) <= 3 && abs($1 - codeFill[1]) <= 3 && abs($2 - codeFill[2]) <= 3
            }
            #expect(codeFill != [255, 255, 255] && fill > 0.005, "\(name): code fill \(codeFill) covers \(fill)")

            let text = (printed.pdf.string ?? "").filter { !$0.isWhitespace }
            #expect(text.contains(Self.longLine), "\(name): the long code line wraps, unclipped")
            #expect(text.contains("Bodytextforthepapersizecheck"))

            // The theme's fonts, at a paper text size.
            let fonts = PrintedPage.fontNames(on: printed.page)
            let serif = fonts.contains { $0.contains("NewYork") }
            #expect(serif == (themeID == "serif"), "\(name): \(fonts)")
            #expect(fonts.contains { $0.contains("Mono") || $0.contains("Menlo") }, "\(name): monospaced code \(fonts)")
            let size = try #require(PrintedPage.pointSize(of: "Body text", on: printed.page))
            #expect((11...13).contains(size), "\(name): body text prints at \(size)pt")
        }

        // Dark mode changes nothing on paper.
        #expect(abs(light.raster.meanLightness - dark.raster.meanLightness) < 0.001)
        #expect(PrintedPage.fontNames(on: light.page).sorted() == PrintedPage.fontNames(on: dark.page).sorted())
    }

    @Test("a custom theme's print rules apply, but can't print a dark page or clip code")
    func customThemePrintRules() async throws {
        defer { closeAll() }
        let custom = Theme(
            id: "custom:dark-paper", displayName: "Dark Paper",
            background: ThemeBackground(light: ThemeColor(0x10_10_10), dark: ThemeColor(0x00_00_00)),
            stylesheet: """
                .markdown-body { color: #eeeeee; }
                .markdown-body h1 { color: rgb(0, 160, 0); }
                """,
            printStylesheet: """
                :root, body { background: #000000 !important; print-color-adjust: exact !important; }
                :root { color-scheme: dark !important; }
                pre { white-space: pre !important; overflow: hidden !important; }
                pre code { white-space: pre !important; }
                .markdown-body h1 { color: rgb(0, 0, 200); }
                """)
        let registry = ThemeRegistry.bundled.adding([custom])
        let (printed, _) = try await print(themeID: custom.id, appearance: .darkAqua, registry: registry)
        #expect(printed.raster.meanLightness > 0.85, "no dark page: \(printed.raster.meanLightness)")
        let text = (printed.pdf.string ?? "").filter { !$0.isWhitespace }
        #expect(text.contains(Self.longLine), "code still wraps")
        // The theme's own (non-protected) print rule applies: the title prints blue, not green.
        #expect(printed.raster.fraction { $0 < 60 && $1 < 60 && $2 > 150 } > 0.0005, "the theme's print color")
        #expect(printed.raster.fraction { $0 < 60 && $1 > 130 && $2 < 60 } < 0.0001, "not its screen color")
    }
}
