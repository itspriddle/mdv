import AppKit
import Foundation
import PDFKit
import PeepCore
import Testing
import WebKit

@testable import PeepApp

/// Visual regression check for the bundled themes (#39): the showcase fixture rendered by real
/// WebKit in each theme, light, dark, and printed, compared with committed reference images.
///
/// Screen modes use `WKWebView.pdf(configuration:)`, which draws the whole page (not just the
/// visible part) as the screen shows it, in the window's appearance; print mode is the Save as
/// PDF path. Both are rasterized here at one pixel per point, so the result doesn't depend on
/// the display's scale factor or on the window being on screen.
///
/// References live per macOS major version in `AppTests/Snapshots/macOS-<major>/`, because
/// text rendering and system font metrics differ between releases (CI runs macOS 26). Record:
///
///     make record-theme-snapshots
///
/// On a mismatch, the actual, reference, and diff images go to `build/theme-snapshots/`.
/// `PEEP_RECORD_MISSING_SNAPSHOTS=1` writes a missing reference there (under `recorded/`) and
/// passes, so CI can record a new macOS version's set as an artifact.
@MainActor
@Suite("Theme snapshots", .serialized, .timeLimit(.minutes(2)))
final class ThemeSnapshotTests: DocumentWindowTestCase {
    enum Mode: String, CaseIterable, Sendable {
        case light, dark, print
    }

    /// The repository root, from this file's path (the tests run from the source tree).
    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    static let fixtures = root.appending(path: "AppUITests/Fixtures/themes", directoryHint: .isDirectory)
    static let osFolder = "macOS-\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)"
    static let references = root.appending(path: "AppTests/Snapshots/\(osFolder)", directoryHint: .isDirectory)
    static let output = root.appending(path: "build/theme-snapshots/\(osFolder)", directoryHint: .isDirectory)
    static let recorded = root.appending(
        path: "build/theme-snapshots/recorded/\(osFolder)", directoryHint: .isDirectory)
    /// The web view's width in points: wide enough for every theme's column and margins.
    static let width: CGFloat = 900
    /// Mismatched pixels allowed per image. Antialiasing noise is absorbed per pixel (see
    /// `SnapshotDiff`), so this only covers stray specks; a changed link color alone is more.
    static let allowedMismatches = 40

    static var environment: [String: String] { ProcessInfo.processInfo.environment }
    static var isRecording: Bool { environment["PEEP_RECORD_SNAPSHOTS"] == "1" }
    static var recordsMissing: Bool { environment["PEEP_RECORD_MISSING_SNAPSHOTS"] == "1" }

    nonisolated static let arguments: [(String, Mode)] = ThemeRegistry.bundled.themes.flatMap { theme in
        Mode.allCases.map { (theme.id, $0) }
    }

    @Test("each bundled theme matches its reference", arguments: arguments)
    func matchesReference(themeID: String, mode: Mode) async throws {
        defer { closeAll() }
        let actual = try await render(themeID: themeID, mode: mode)
        try compare(actual, name: "\(themeID)-\(mode.rawValue)")
    }

    /// Every bundled theme and mode has a reference for this macOS version, and nothing else does.
    @Test("the references match the bundled themes")
    func referencesAreComplete() throws {
        guard !Self.isRecording, !Self.recordsMissing else {
            return
        }
        let expected = Set(Self.arguments.map { "\($0.0)-\($0.1.rawValue).png" })
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.references.path)
        #expect(Set(files.filter { $0.hasSuffix(".png") }) == expected, "\(Self.references.path)")
    }

    /// Renders the showcase in `themeID`: the whole page as the screen shows it in light or dark,
    /// or every printed page stacked top to bottom.
    func render(themeID: String, mode: Mode) async throws -> SnapshotImage {
        let assets = folder.appending(path: "assets", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: assets.path) {
            try FileManager.default.copyItem(at: Self.fixtures.appending(path: "assets"), to: assets)
        }
        let source = try String(contentsOf: Self.fixtures.appending(path: "showcase.md"), encoding: .utf8)
        let (document, controller) = try await openShowcase(
            source, name: "showcase-\(themeID)-\(mode.rawValue).md", themeID: themeID,
            appearance: mode == .dark ? .darkAqua : .aqua)
        #expect(controller.theme.id == themeID)
        let webView = controller.coordinator.webView
        #expect(webView.frame.width == Self.width, "the web view is \(webView.frame.width) wide")
        // Images decoded and fonts loaded. No requestAnimationFrame: it doesn't fire in a
        // window that isn't on screen.
        _ = try await webView.callAsyncJavaScript(
            """
            await Promise.all(Array.from(document.images).map((img) => img.decode().catch(() => null)));
            await document.fonts.ready;
            await new Promise((resolve) => setTimeout(resolve, 50));
            """, arguments: [:], in: nil, contentWorld: AppScripts.world)
        switch mode {
        case .light, .dark:
            let data = try await webView.pdf(configuration: WKPDFConfiguration())
            let pdf = try #require(PDFDocument(data: data))
            return try SnapshotImage(pages: pages(of: pdf))
        case .print:
            let pdf = try await printToPDF(document, in: controller, named: "showcase-\(themeID).pdf")
            return try SnapshotImage(pages: pages(of: pdf))
        }
    }

    func pages(of pdf: PDFDocument) -> [PDFPage] {
        (0..<pdf.pageCount).compactMap { pdf.page(at: $0) }
    }

    /// Opens `source` in `themeID` at a fixed size, with the outline hidden and default zoom and
    /// content width (this suite's throwaway defaults), in `appearance` from the first load.
    func openShowcase(_ source: String, name: String, themeID: String, appearance: NSAppearance.Name) async throws
        -> (MarkdownDocument, DocumentWindowController)
    {
        let file = folder.appending(path: name)
        try Data(source.utf8).write(to: file)
        let document = try MarkdownDocument(contentsOf: file, ofType: Self.markdownType)
        let themes = themeSettings()
        themes.defaultThemeID = themeID
        let controller = DocumentWindowController(
            outlinePreference: OutlinePreference(defaults: defaults, isPersistent: true),
            zoomSettings: settings(),
            contentWidthSettings: ContentWidthSettings(defaults: defaults, isPersistent: true),
            themeSettings: themes)
        let window = try #require(controller.window)
        window.appearance = NSAppearance(named: appearance)
        window.setContentSize(NSSize(width: Self.width, height: 760))
        document.addWindowController(controller)
        documents.append(document)
        try await until("the first load") { controller.coordinator.hasLoadedPage }
        return (document, controller)
    }

    /// Compares `actual` with the reference `name`, recording it instead when asked to.
    func compare(_ actual: SnapshotImage, name: String) throws {
        let file = "\(name).png"
        let reference = Self.references.appending(path: file)
        for suffix in ["actual", "reference", "diff"] {
            try? FileManager.default.removeItem(at: Self.output.appending(path: "\(name).\(suffix).png"))
        }
        if Self.isRecording {
            try actual.writePNG(to: reference)
            return
        }
        guard FileManager.default.fileExists(atPath: reference.path) else {
            if Self.recordsMissing {
                try actual.writePNG(to: Self.recorded.appending(path: file))
                print("ThemeSnapshotTests: no reference \(reference.path); recorded it under \(Self.recorded.path)")
            } else {
                try actual.writePNG(to: Self.output.appending(path: "\(name).actual.png"))
                Issue.record(
                    """
                    No reference for \(name) on \(Self.osFolder) (\(reference.path)). Record with \
                    `make record-theme-snapshots`; the actual image is in \(Self.output.path).
                    """)
            }
            return
        }
        let expected = try SnapshotImage(contentsOf: reference)
        let diff = SnapshotDiff(actual: actual, reference: expected)
        let passes = diff.map { $0.mismatchedPixels <= Self.allowedMismatches } ?? false
        guard !passes else {
            return
        }
        try actual.writePNG(to: Self.output.appending(path: "\(name).actual.png"))
        try expected.writePNG(to: Self.output.appending(path: "\(name).reference.png"))
        try diff?.image.writePNG(to: Self.output.appending(path: "\(name).diff.png"))
        let summary =
            diff.map { "\($0.mismatchedPixels) pixels differ (\(Self.allowedMismatches) allowed)" }
            ?? "size \(actual.width)x\(actual.height), reference \(expected.width)x\(expected.height)"
        Issue.record(
            """
            \(name) doesn't match its \(Self.osFolder) reference: \(summary). Images in \
            \(Self.output.path). If the change is intended, run `make record-theme-snapshots`.
            """)
    }
}
