import AppKit
import Foundation
import PeepCore
import Testing

@testable import PeepApp

/// Feedback for slow renders (#58): the progress indicator shows only once a wait outlasts its
/// delay (injected here), over the blank page before the first page loads and in the corner
/// while a newer render runs over the old page; it goes when the wait ends. The outline fills
/// only after the first page has loaded.
@MainActor
@Suite("Render progress", .serialized, .timeLimit(.minutes(2)))
final class RenderProgressTests: DocumentWindowTestCase {
    /// Short, so tests don't wait 300 ms for each indicator.
    static let delay: Duration = .milliseconds(50)

    var scripts: PreprocessorScripts { PreprocessorScripts(folder: folder) }

    /// The page's text; empty before the first page loads.
    func bodyText(_ controller: DocumentWindowController) async throws -> String {
        guard controller.coordinator.hasLoadedPage else {
            return ""
        }
        return try await controller.coordinator.webView.callAsyncJavaScript(
            "return document.querySelector('.markdown-body').textContent;", arguments: [:], in: nil,
            contentWorld: AppScripts.world) as? String ?? ""
    }

    /// Opens `source` in a window with `progress`, rendering with `customPreprocessorSettings`
    /// (none unless given), without waiting for anything.
    func openWindow(
        _ source: String, name: String = "notes.md", progress: RenderProgress,
        customPreprocessorSettings: CustomPreprocessorSettings? = nil, outlineVisible: Bool = false
    ) throws -> (MarkdownDocument, DocumentWindowController) {
        let file = folder.appending(path: name)
        try Data(source.utf8).write(to: file)
        let document = try MarkdownDocument(contentsOf: file, ofType: Self.markdownType)
        if let customPreprocessorSettings {
            document.customPreprocessorSettings = customPreprocessorSettings
        }
        documents.append(document)
        let outlinePreference = OutlinePreference(defaults: defaults, isPersistent: true)
        outlinePreference.showsOutlineInNewWindows = outlineVisible
        let controller = DocumentWindowController(
            outlinePreference: outlinePreference, zoomSettings: settings(),
            contentWidthSettings: ContentWidthSettings(defaults: defaults, isPersistent: true),
            themeSettings: themeSettings(), renderProgress: progress)
        document.addWindowController(controller)
        return (document, controller)
    }

    // MARK: The delay

    @Test("shows only once the wait outlasts the delay, and goes as soon as it ends")
    func delay() async throws {
        let progress = RenderProgress(delay: Self.delay)
        progress.update(isWaitingForFirstPage: true, isRendering: true)
        #expect(progress.indicator == nil, "not before the delay")
        try await until("the indicator") { progress.indicator == .firstPage }
        progress.update(isWaitingForFirstPage: false, isRendering: false)
        #expect(progress.indicator == nil, "gone at once")
    }

    @Test("a wait shorter than the delay never shows it")
    func shortWait() async throws {
        let progress = RenderProgress(delay: Self.delay)
        progress.update(isWaitingForFirstPage: true, isRendering: true)
        try await Task.sleep(for: Self.delay / 2)
        progress.update(isWaitingForFirstPage: false, isRendering: false)
        try await Task.sleep(for: Self.delay * 3)
        #expect(progress.indicator == nil)

        // Nor does a new wait inherit the old one's time.
        progress.update(isWaitingForFirstPage: false, isRendering: true)
        #expect(progress.indicator == nil)
        try await until("the update indicator") { progress.indicator == .update }
    }

    @Test("an indicator already showing changes kind at once")
    func changesKind() async throws {
        let progress = RenderProgress(delay: Self.delay)
        progress.update(isWaitingForFirstPage: true, isRendering: true)
        try await until("the indicator") { progress.indicator == .firstPage }
        progress.update(isWaitingForFirstPage: false, isRendering: true)
        #expect(progress.indicator == .update)
        progress.update(isWaitingForFirstPage: false, isRendering: false)
        #expect(progress.indicator == nil)
    }

    @Test("the default delay is 300 ms")
    func defaultDelay() {
        #expect(RenderProgress.defaultDelay == .milliseconds(300))
        #expect(RenderProgress().delay == .milliseconds(300))
    }

    // MARK: Windows

    @Test("a slow first render shows the indicator over the blank page until the first page loads")
    func slowFirstRender() async throws {
        defer { closeAll() }
        let store = PreprocessorScripts.settings(running: try scripts.slow(seconds: 1), defaults: defaults)
        let progress = RenderProgress(delay: Self.delay)
        let (document, controller) = try openWindow(
            "# Slow\n\nText.\n", progress: progress, customPreprocessorSettings: store)
        #expect(document.isRendering)
        #expect(progress.indicator == nil, "not before the delay")
        try await until("the indicator") { progress.indicator == .firstPage }
        #expect(document.content == nil, "still rendering")
        #expect(!controller.coordinator.webView.isOpaque, "over the theme background")

        try await until("the first page") { controller.coordinator.hasLoadedPage }
        #expect(progress.indicator == nil, "gone at first paint")
        #expect(!document.isRendering)
        #expect(try await bodyText(controller).contains("Text."))
    }

    @Test("a fast open doesn't show it")
    func fastOpen() async throws {
        defer { closeAll() }
        // A window first, so the measured open isn't the test process's first web view.
        _ = try await open("# Warm\n", name: "warm.md")
        let progress = RenderProgress()
        var shown = false
        let start = ContinuousClock.now
        let (_, controller) = try openWindow("# Fast\n\nText.\n", progress: progress)
        while !controller.coordinator.hasLoadedPage {
            shown = shown || progress.indicator != nil
            try await Task.sleep(for: .milliseconds(5))
        }
        let elapsed = ContinuousClock.now - start
        #expect(progress.indicator == nil)
        // A loaded machine can take longer than the delay to load even a small page; the
        // indicator is right to show then.
        if elapsed < RenderProgress.defaultDelay {
            #expect(!shown, "loaded in \(elapsed)")
        }
    }

    @Test("a slow live reload keeps the old page and shows the small indicator until it lands")
    func slowLiveReload() async throws {
        defer { closeAll() }
        let script = try scripts.write("slow-lower.sh", "sleep 1\ntr '[:upper:]' '[:lower:]'")
        let store = PreprocessorScripts.settings(running: script, defaults: defaults)
        let progress = RenderProgress(delay: Self.delay)
        let (document, controller) = try openWindow(
            "FIRST VERSION\n", progress: progress, customPreprocessorSettings: store)
        document.startLiveReload()
        try await until("the first page") { controller.coordinator.hasLoadedPage }
        try await until("no render in flight") { !document.isRendering && progress.indicator == nil }

        try Data("SECOND VERSION\n".utf8).write(to: try #require(document.fileURL))
        try await until("the update indicator") { progress.indicator == .update }
        #expect(document.isRendering)
        #expect(try await bodyText(controller).contains("first version"), "the old page stays")

        try await until("the reload") { try await bodyText(controller).contains("second version") }
        #expect(progress.indicator == nil)
        #expect(!document.isRendering)
    }

    @Test("a Settings change that re-renders slowly shows the small indicator")
    func slowSettingsReRender() async throws {
        defer { closeAll() }
        let store = PreprocessorScripts.settings(running: try scripts.upcase(), defaults: defaults)
        let progress = RenderProgress(delay: Self.delay)
        let (document, controller) = try openWindow(
            "Mixed Case.\n", progress: progress, customPreprocessorSettings: store)
        try await until("the processed page") { try await bodyText(controller).contains("MIXED CASE.") }

        store.executablePath = try scripts.slow(seconds: 1)
        try await until("the update indicator") { progress.indicator == .update }
        #expect(try await bodyText(controller).contains("MIXED CASE."), "the old page stays")
        try await until("the re-render") { try await bodyText(controller).contains("Mixed Case.") }
        #expect(progress.indicator == nil)
        #expect(!document.isRendering)
    }

    @Test("the window follows its theme's background, for the indicator's contrast")
    func background() throws {
        defer { closeAll() }
        let progress = RenderProgress(delay: Self.delay)
        let (_, controller) = try openWindow("# Theme\n", progress: progress)
        #expect(progress.background == controller.theme.background)
        controller.setTheme(id: Theme.serif.id)
        #expect(progress.background == Theme.serif.background)
    }

    // MARK: Outline

    @Test("the outline fills only after the first page has loaded")
    func outlineAfterFirstPage() async throws {
        defer { closeAll() }
        let store = PreprocessorScripts.settings(running: try scripts.slow(seconds: 0.5), defaults: defaults)
        let progress = RenderProgress(delay: Self.delay)
        let (document, controller) = try openWindow(
            "# One\n\n## Two\n", progress: progress, customPreprocessorSettings: store, outlineVisible: true)
        let outline = controller.outlineController
        let empty = outline.view.subviews.first { $0.accessibilityIdentifier() == "document-outline-empty" }
        #expect(empty?.isHidden == true, "no \"No Headings\" while rendering")
        // Watch for the outline filling before the page has loaded.
        var filledEarly = false
        while !controller.coordinator.hasLoadedPage {
            filledEarly = filledEarly || outline.hasOutline
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(document.content != nil)
        #expect(!filledEarly, "filled before the first page loaded")
        try await until("the outline") { outline.hasOutline }
        #expect(outline.tracker.outline.headings.map(\.slug) == ["one", "two"])

        // Later content fills it as it is shown.
        document.setContent(DocumentContent(source: "# Three\n", fallbackTitle: "notes.md"))
        #expect(outline.tracker.outline.headings.map(\.slug) == ["three"])
    }
}
