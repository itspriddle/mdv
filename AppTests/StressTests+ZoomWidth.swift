import AppKit
import Foundation
import MdvCore
import Testing
import WebKit

@testable import MdvApp

/// Per-window zoom and content width (#47) under load: interleaved changes across windows
/// racing live reloads and reverts. Each window must end on its own last values, in the window
/// and in the page, with nothing leaking into another window or into Settings.
extension StressTests {
    /// The text of the page's `mdv-user` layer.
    func pageUserCSS(_ controller: DocumentWindowController) async throws -> String? {
        (try await controller.coordinator.webView.callAsyncJavaScript(
            "return document.getElementById('mdv-user').textContent;", arguments: [:], in: nil,
            contentWorld: AppScripts.world) as? String)?
            .trimmingCharacters(in: .newlines)
    }

    /// Opens `url` in a window that starts from `zoomSettings` and `contentWidthSettings` and
    /// live reloads, as `makeWindowControllers()` does, without waiting for the page.
    func open(
        _ url: URL, zoomSettings: ZoomSettings, contentWidthSettings: ContentWidthSettings
    ) throws -> (MarkdownDocument, DocumentWindowController) {
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        let controller = DocumentWindowController(
            zoomSettings: zoomSettings, contentWidthSettings: contentWidthSettings)
        document.addWindowController(controller)
        document.startLiveReload()
        document.showWindows()
        return (document, controller)
    }

    @Test("per-window zoom and width changes during rapid live reloads end on each window's own values")
    func zoomAndWidthDuringReloads() async throws {
        let defaults = try ThrowawayDefaults("mdv-stress")
        let zoom = ZoomSettings(defaults: defaults.defaults, isPersistent: true)
        let width = ContentWidthSettings(defaults: defaults.defaults, isPersistent: true)
        let urls = try (0..<4).map { try write("# Start \($0)", to: "zoomed-\($0).md") }
        let windows = try urls.map { try open($0, zoomSettings: zoom, contentWidthSettings: width) }
        defer {
            for (document, _) in windows {
                document.close()
            }
        }

        let widths = ContentWidth.allCases
        // Each window's expected level, stepped as its commands are; the schedules hit both ends.
        var expectedLevels = windows.map(\.1.zoomLevel)
        for step in 1...40 {
            for (index, url) in urls.enumerated() {
                try Data("# Step \(step) of \(index)\n\n\(String(repeating: "word ", count: step * 40))".utf8)
                    .write(to: url)
            }
            for (index, (document, controller)) in windows.enumerated() {
                // Each window steps on its own schedule, so windows end on different values.
                if (step * (index + 1)).isMultiple(of: 4) {
                    controller.zoomInDocument(nil)
                    expectedLevels[index] = PageZoom.larger(than: expectedLevels[index]) ?? expectedLevels[index]
                }
                if (step + index).isMultiple(of: 3) {
                    controller.zoomOutDocument(nil)
                    expectedLevels[index] = PageZoom.smaller(than: expectedLevels[index]) ?? expectedLevels[index]
                }
                controller.setContentWidth(to: widths[(step + index) % widths.count])
                if step.isMultiple(of: 9) {
                    try document.revert(toContentsOf: try #require(document.fileURL), ofType: Self.markdownType)
                }
            }
            if step.isMultiple(of: 10) {
                // A Settings change mid-churn reaches no open window.
                zoom.defaultLevel = step.isMultiple(of: 20) ? 1 : 2
                width.defaultWidth = step.isMultiple(of: 20) ? .theme : .full
            }
            try await Task.sleep(for: .milliseconds(step.isMultiple(of: 5) ? 120 : 5))
        }

        #expect(windows.map(\.1.zoomLevel) == expectedLevels)
        #expect(Set(expectedLevels).count > 1, "windows end on different levels: \(expectedLevels)")
        for (index, (document, controller)) in windows.enumerated() {
            try await until("final content \(index)") { try await pageTitle(controller) == "Step 40 of \(index)" }
            #expect(document.fileStatus == .current)
            let expectedWidth = widths[(40 + index) % widths.count]
            #expect(controller.contentWidth == expectedWidth, "window \(index)")
            #expect(abs(controller.coordinator.webView.pageZoom - expectedLevels[index]) < 0.001, "window \(index)")
            let css = UserStyle(contentWidth: expectedWidth).layerCSS.trimmingCharacters(in: .newlines)
            try await until("window \(index) page width") { try await pageUserCSS(controller) == css }
        }
        #expect(zoom.defaultLevel == 1)
        #expect(width.defaultWidth == .theme)
    }
}
