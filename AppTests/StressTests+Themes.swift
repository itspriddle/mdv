import AppKit
import Foundation
import PeepCore
import Testing
import WebKit

@testable import PeepApp

/// The M3 crash and hang pass (#45): theme switches racing live reloads, and custom themes
/// added, edited, broken, and deleted (in a temporary folder, never the reader's) while windows
/// open and close. Run under the Address and Thread Sanitizers as well (docs/ROADMAP.md, M3).
extension StressTests {
    /// Theme settings over a throwaway defaults suite, so nothing reaches the reader's defaults.
    func themeSettings(_ defaults: ThrowawayDefaults) -> ThemeSettings {
        ThemeSettings(defaults: defaults.defaults, isPersistent: true)
    }

    /// Opens `url` in a window that follows `themeSettings` and live reloads, as
    /// `makeWindowControllers()` does, without waiting for the page.
    func open(_ url: URL, themeSettings: ThemeSettings) throws -> (MarkdownDocument, DocumentWindowController) {
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        let controller = DocumentWindowController(themeSettings: themeSettings)
        document.addWindowController(controller)
        document.startLiveReload()
        document.showWindows()
        return (document, controller)
    }

    /// The text of the page's `peep-theme` layer.
    func pageThemeCSS(_ controller: DocumentWindowController) async throws -> String? {
        (try await controller.coordinator.webView.callAsyncJavaScript(
            "return document.getElementById('peep-theme').textContent;", arguments: [:], in: nil,
            contentWorld: AppScripts.world) as? String)?
            .trimmingCharacters(in: .newlines)
    }

    /// Waits until `controller` shows `theme`, in the window and in the page.
    func untilShowing(_ theme: Theme, in controller: DocumentWindowController, _ what: String) async throws {
        let css = theme.layerCSS.trimmingCharacters(in: .newlines)
        try await until("\(what) shows \(theme.id)", timeout: .seconds(15)) {
            guard controller.theme == theme else {
                return false
            }
            return try await pageThemeCSS(controller) == css
        }
    }

    @Test("theme switches during rapid live reloads end on the newest content and the last theme")
    func themeSwitchDuringReloads() async throws {
        let defaults = try ThrowawayDefaults("peep-stress")
        let settings = themeSettings(defaults)
        let themes = settings.registry.themes
        let urls = try (0..<4).map { try write("# Start \($0)", to: "themed-\($0).md") }
        let windows = try urls.map { try open($0, themeSettings: settings) }
        defer {
            for (document, _) in windows {
                document.close()
            }
        }
        for (_, controller) in windows {
            try await until("first load") { controller.coordinator.hasLoadedPage }
        }
        let steps = 30
        for step in 1...steps {
            for (index, url) in urls.enumerated() {
                try Data("# Step \(step) of \(index)\n\n\(String(repeating: "word ", count: step * 40))".utf8)
                    .write(to: url)
                windows[index].1.setTheme(id: themes[(step + index) % themes.count].id)
            }
            if step.isMultiple(of: 4) {
                // Settings' default changing too; it only affects new windows.
                settings.defaultThemeID = themes[step % themes.count].id
            }
            // Switch again right after a turn, while the reload and the last swap are in flight.
            await Task.yield()
            windows[step % windows.count].1.setTheme(id: themes[(step * 7) % themes.count].id)
            try await Task.sleep(for: .milliseconds(step.isMultiple(of: 5) ? 120 : 5))
        }
        for (index, (document, controller)) in windows.enumerated() {
            try await until("final content \(index)", timeout: .seconds(15)) {
                try await pageTitle(controller) == "Step \(steps) of \(index)"
            }
            #expect(document.fileStatus == .current)
            try await untilShowing(settings.registry.theme(id: controller.themeID), in: controller, "window \(index)")
        }
    }

    @Test("custom themes added, edited, broken, and deleted while windows open and close")
    func customThemeChurn() async throws {
        let defaults = try ThrowawayDefaults("peep-stress")
        let settings = themeSettings(defaults)
        let themes = try ChurningThemesFolder(folder.appending(path: "Themes", directoryHint: .isDirectory))
        let library = CustomThemeLibrary(
            folder: themes.folder, settings: settings,
            timing: ThemeFolderWatcher.Timing(latency: .milliseconds(20), maximumLatency: .milliseconds(80)))
        library.start()
        defer { library.stop() }
        // New windows start on a custom theme that comes and goes.
        settings.defaultThemeID = "custom:b.css"

        let urls = try (0..<4).map { index in
            try write(
                "# Doc \(index)\n\n" + (1...100).map { "Paragraph \($0)." }.joined(separator: "\n\n"),
                to: "custom-\(index).md")
        }
        var open: [(MarkdownDocument, DocumentWindowController)] = []
        defer {
            for (document, _) in open {
                document.close()
            }
        }
        for round in 0..<12 {
            try themes.change(round: round)
            for (index, url) in urls.enumerated() where (index + round).isMultiple(of: 2) {
                let opened = try self.open(url, themeSettings: settings)
                if index.isMultiple(of: 3) {
                    opened.1.setTheme(id: "custom:a.css")
                }
                open.append(opened)
            }
            try await closeOldest(of: &open, keeping: 4, round: round)
            try await Task.sleep(for: .milliseconds(round.isMultiple(of: 4) ? 150 : 10))
        }

        try themes.settle()
        try await until("the final catalog", timeout: .seconds(15)) {
            let registry = settings.registry
            return registry.contains(id: "custom:a.css") && !registry.contains(id: "custom:b.css")
                && registry.theme(id: "custom:a.css").stylesheet.contains("42px")
                && registry.contains(id: "custom:c.css") && settings.customThemeFailures.isEmpty
        }
        #expect(settings.registry.contains(id: "custom:extra-11.css"))
        #expect(!settings.registry.contains(id: "custom:extra-9.css"))

        try await expectSettled(open.map(\.1), themeA: settings.registry.theme(id: "custom:a.css"))
        // A window opened now still works and shows the fallback.
        let (document, controller) = try self.open(urls[0], themeSettings: settings)
        open.append((document, controller))
        try await until("the final load") { controller.coordinator.hasLoadedPage }
        #expect(try await pageTitle(controller) == "Doc 0")
    }

    /// After `ChurningThemesFolder.settle()`: windows on `a.css` show its final version; the
    /// others picked `b.css` (Settings' default), which is gone, as is that default, so they show
    /// GitHub, the registry's default.
    func expectSettled(_ controllers: [DocumentWindowController], themeA: Theme) async throws {
        for (index, controller) in controllers.enumerated() {
            try await until("load \(index)", timeout: .seconds(15)) { controller.coordinator.hasLoadedPage }
            if controller.themeID == themeA.id {
                try await untilShowing(themeA, in: controller, "window \(index)")
            } else {
                #expect(controller.themeID == "custom:b.css")
                try await untilShowing(ThemeRegistry.bundled.defaultTheme, in: controller, "window \(index)")
            }
        }
    }

    /// Closes the oldest windows until `count` are left: some mid-load, some after a turn, some
    /// once loaded.
    func closeOldest(
        of windows: inout [(MarkdownDocument, DocumentWindowController)], keeping count: Int, round: Int
    ) async throws {
        while windows.count > count {
            let (document, controller) = windows.removeFirst()
            switch (round + windows.count) % 3 {
            case 0:
                document.close()
            case 1:
                await Task.yield()
                document.close()
            default:
                try await until("a load before closing", timeout: .seconds(15)) { controller.coordinator.hasLoadedPage }
                document.close()
            }
        }
    }
}

/// A custom themes folder that changes every round: `a.css` edited, `b.css` deleted and
/// recreated, `c.css` broken and fixed, and `extra-<round>.css` added while older ones go.
private struct ChurningThemesFolder {
    let folder: URL

    init(_ folder: URL) throws {
        self.folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func write(_ css: String, to name: String) throws {
        try Data(css.utf8).write(to: folder.appending(path: name), options: .atomic)
    }

    func delete(_ name: String) {
        try? FileManager.default.removeItem(at: folder.appending(path: name))
    }

    func change(round: Int) throws {
        try write(".markdown-body { letter-spacing: \(round)px; }", to: "a.css")
        if round.isMultiple(of: 3) {
            delete("b.css")
        } else {
            try write("/* peep-theme\nname: B\nextends: serif\n*/\np { margin: \(round)px; }", to: "b.css")
        }
        // Broken on odd rounds (shown as a failure), valid on even ones.
        try write(round.isMultiple(of: 2) ? "p { color: red; }" : "@import 'x.css';", to: "c.css")
        try write("p {}", to: "extra-\(round).css")
        delete("extra-\(round - 2).css")
    }

    /// The final state: `a.css` at 42px, `b.css` gone, `c.css` valid.
    func settle() throws {
        try write(".markdown-body { letter-spacing: 42px; }", to: "a.css")
        delete("b.css")
        try write("p { color: blue; }", to: "c.css")
    }
}
