import AppKit
import Foundation
import MdvCore
import Testing
import WebKit

@testable import MdvApp

/// The M4 crash and hang pass (#59): Settings > Markdown changing while renders and live
/// reloads are in flight, frontmatter overrides (`mdv.theme`, `mdv.flavor`) changing under live
/// reload, and a custom preprocessor that switches between hanging, crashing, flooding, and
/// failing as the file changes. Run under the Address and Thread Sanitizers as well
/// (docs/ROADMAP.md, M4).
extension StressTests {
    /// Opens `url` in a window that renders with `markdownSettings` and `themeSettings` and live
    /// reloads, as `makeWindowControllers()` does, without waiting for the page.
    func open(
        _ url: URL, markdownSettings: MarkdownSettings, themeSettings: ThemeSettings? = nil,
        preprocessor: CustomPreprocessorSettings? = nil
    ) throws -> (MarkdownDocument, DocumentWindowController) {
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        document.markdownSettings = markdownSettings
        if let preprocessor {
            document.customPreprocessorSettings = preprocessor
        }
        let controller =
            themeSettings.map { DocumentWindowController(themeSettings: $0) } ?? DocumentWindowController()
        document.addWindowController(controller)
        document.startLiveReload()
        document.showWindows()
        return (document, controller)
    }

    /// Whether the page has an element matching `selector` inside the Markdown body.
    func pageHas(_ selector: String, in controller: DocumentWindowController) async throws -> Bool {
        try await controller.coordinator.webView.callAsyncJavaScript(
            "return document.querySelector(sel) !== null;", arguments: ["sel": ".markdown-body \(selector)"],
            in: nil, contentWorld: AppScripts.world) as? Bool ?? false
    }

    /// A document with a table, a wiki link, and frontmatter: each Settings > Markdown option
    /// changes how it renders.
    static func settingsSource(step: Int, index: Int) -> String {
        """
        ---
        step: \(step)
        ---
        # Step \(step) of \(index)

        | Alpha | Beta |
        | ----- | ---- |
        | \(step) | \(index) |

        See [[Some Page]]. \(String(repeating: "word ", count: step * 20))
        """
    }

    @Test("Settings > Markdown changes during first renders and rapid live reloads end on the newest settings")
    func settingsChangesDuringRenders() async throws {
        let defaults = try ThrowawayDefaults("mdv-stress")
        let settings = MarkdownSettings(defaults: defaults.defaults, isPersistent: true)
        let urls = try (0..<4).map { try write(Self.settingsSource(step: 0, index: $0), to: "settings-\($0).md") }
        // A large document whose first render is still in flight while the settings change.
        let large = try write(FirstRenderTests.largeSource(bytes: 1_000_000), to: "settings-large.md")
        var windows = try urls.map { try open($0, markdownSettings: settings) }
        let largeWindow = try open(large, markdownSettings: settings)
        windows.append(largeWindow)
        defer {
            for (document, _) in windows {
                document.close()
            }
        }
        // Correctness only: no heartbeat, since the windows' first page loads (the 1 MB one
        // included) land during the churn by design.
        let flavors = settings.registry.flavors.map(\.id)
        let steps = 30
        for step in 1...steps {
            for (index, url) in urls.enumerated() {
                try Data(Self.settingsSource(step: step, index: index).utf8).write(to: url)
            }
            await change(settings, step: step, flavors: flavors)
            try await Task.sleep(for: .milliseconds(step.isMultiple(of: 5) ? 120 : 5))
        }
        let expected = settings.preferences
        for (index, (document, controller)) in windows.enumerated() {
            try await until("window \(index) renders with the final settings", timeout: .seconds(30)) {
                controller.coordinator.hasLoadedPage && document.content?.preferences == expected
                    && !document.isRendering
            }
            #expect(document.fileStatus == .current)
        }
        for (index, (_, controller)) in windows.dropLast().enumerated() {
            try await until("final content \(index)", timeout: .seconds(15)) {
                try await pageTitle(controller) == "Step \(steps) of \(index)"
            }
            #expect(try await pageHas("table:not(.frontmatter)", in: controller) == (expected.flavor.id == "gfm"))
            #expect(try await pageHas("table.frontmatter", in: controller) == (expected.frontmatterDisplay == .table))
            #expect(
                try await pageHas("a.wikilink", in: controller) == expected.builtInPreprocessors.contains(.wikiLinks))
        }
        #expect(try await pageTitle(largeWindow.1) == "Large Document")
    }

    /// Changes every Settings > Markdown option for `step`, then the flavor again right after a
    /// turn, while the reloads and re-renders it started are in flight.
    func change(_ settings: MarkdownSettings, step: Int, flavors: [String]) async {
        settings.defaultFlavorID = flavors[step % flavors.count]
        if step.isMultiple(of: 2) {
            settings.frontmatterDisplay = step.isMultiple(of: 4) ? .table : .hidden
        }
        if step.isMultiple(of: 3) {
            settings.builtInPreprocessors = settings.builtInPreprocessors.isEmpty ? [.wikiLinks] : []
        }
        await Task.yield()
        settings.defaultFlavorID = flavors[(step + 1) % flavors.count]
    }

    /// A document whose frontmatter overrides its theme and flavor (#54).
    nonisolated static func overrideSource(step: Int, index: Int, theme: String, flavor: String) -> String {
        """
        ---
        mdv:
          theme: \(theme)
          flavor: \(flavor)
        ---
        # Step \(step) of \(index)

        | Alpha | Beta |
        | ----- | ---- |
        | \(step) | \(index) |

        \(String(repeating: "word ", count: step * 30))
        """
    }

    @Test("frontmatter theme and flavor overrides changing under rapid live reloads end on the newest ones")
    func frontmatterOverridesDuringReloads() async throws {
        let defaults = try ThrowawayDefaults("mdv-stress")
        let markdownSettings = MarkdownSettings(defaults: defaults.defaults, isPersistent: true)
        let themeStore = themeSettings(defaults)
        let themes = themeStore.registry.themes.map(\.id)
        let flavors = markdownSettings.registry.flavors.map(\.id)
        let urls = try (0..<4).map { index in
            try write(
                Self.overrideSource(step: 0, index: index, theme: themes[0], flavor: flavors[0]),
                to: "override-\(index).md")
        }
        let windows = try urls.map { try open($0, markdownSettings: markdownSettings, themeSettings: themeStore) }
        defer {
            for (document, _) in windows {
                document.close()
            }
        }
        for (_, controller) in windows {
            try await until("first load") { controller.coordinator.hasLoadedPage }
        }
        let heartbeat = MainThreadHeartbeat()
        heartbeat.start()
        defer { heartbeat.stop() }
        let plan = OverridePlan(themes: themes, flavors: flavors)
        for step in 1...plan.steps {
            for (index, url) in urls.enumerated() {
                try Data(plan.source(step: step, index: index).utf8).write(to: url)
            }
            // The reader picks a theme in one window, drops it later, and changes the defaults.
            switch step {
            case 8:
                windows[0].1.setTheme(id: themes[1])
            case 20:
                windows[0].1.clearThemePick()
            case 12:
                windows[1].1.setTheme(id: plan.pickInSecondWindow)
            default:
                break
            }
            if step.isMultiple(of: 5) {
                themeStore.defaultThemeID = themes[step % themes.count]
                markdownSettings.defaultFlavorID = flavors[step % flavors.count]
            }
            try await Task.sleep(for: .milliseconds(step.isMultiple(of: 6) ? 150 : 10))
        }
        for (index, window) in windows.enumerated() {
            try await expectFinal(window, index: index, plan: plan, registry: themeStore.registry)
        }
        #expect(heartbeat.longestBusyGap < .milliseconds(150), "main thread busy \(heartbeat.longestBusyGap)")
    }

    /// Checks that window `index` settled on the plan's last step: its content, the document's
    /// theme (or the reader's pick in the second window), and the flavor.
    func expectFinal(
        _ window: (MarkdownDocument, DocumentWindowController), index: Int, plan: OverridePlan,
        registry: ThemeRegistry
    ) async throws {
        let (document, controller) = window
        try await until("final content \(index)", timeout: .seconds(15)) {
            try await pageTitle(controller) == "Step \(plan.steps) of \(index)"
        }
        #expect(document.fileStatus == .current)
        #expect(controller.documentThemeID == plan.theme(step: plan.steps, index: index), "window \(index)")
        let shown = index == 1 ? plan.pickInSecondWindow : plan.theme(step: plan.steps, index: index)
        #expect(controller.themeID == shown, "window \(index)")
        try await untilShowing(registry.theme(id: shown), in: controller, "window \(index)")
        let isGFM = plan.flavor(step: plan.steps, index: index) == "gfm"
        #expect(try await pageHas("table", in: controller) == isGFM, "window \(index)")
    }

    @Test("a script that hangs, crashes, floods, or fails as the file changes under live reload")
    func preprocessorMisbehavesDuringReloads() async throws {
        let defaults = try ThrowawayDefaults("mdv-stress")
        let markdownSettings = MarkdownSettings(defaults: defaults.defaults, isPersistent: false)
        let scripts = PreprocessorScripts(folder: folder)
        let preprocessor = PreprocessorScripts.settings(running: try scripts.modal(), defaults: defaults.defaults)
        let modes = ["HANG", "CRASH", "FLOOD", "FAIL", "fine"]
        let urls = try (0..<4).map { try write("# Start \($0)", to: "modal-\($0).md") }
        let windows = try urls.map {
            try open($0, markdownSettings: markdownSettings, preprocessor: preprocessor)
        }
        defer {
            for (document, _) in windows {
                document.close()
            }
        }
        // Timed once the windows are up (starting web content processes isn't the script's).
        for (_, controller) in windows {
            try await until("first load", timeout: .seconds(15)) { controller.coordinator.hasLoadedPage }
        }
        let heartbeat = MainThreadHeartbeat()
        heartbeat.start()
        defer { heartbeat.stop() }
        let steps = 25
        for step in 1...steps {
            for (index, url) in urls.enumerated() {
                let mode = step == steps ? "fine" : modes[(step + index) % modes.count]
                try Data("# Step \(step) of \(index)\n\nMode \(mode).\n".utf8).write(to: url)
            }
            if step.isMultiple(of: 7) {
                // Settings changes restart the runs in flight.
                preprocessor.arguments = preprocessor.arguments.isEmpty ? ["--step"] : []
            }
            // Mostly faster than a run, sometimes long enough for a failure to land.
            try await Task.sleep(for: .milliseconds(step.isMultiple(of: 4) ? 600 : 20))
        }
        for (index, (document, controller)) in windows.enumerated() {
            try await until("final content \(index)", timeout: .seconds(20)) {
                try await pageTitle(controller) == "Step \(steps) of \(index)" && !document.isRendering
            }
            #expect(document.fileStatus == .current)
            #expect(document.content?.preprocessorError == nil, "window \(index)")
        }
        #expect(heartbeat.longestBusyGap < .milliseconds(150), "main thread busy \(heartbeat.longestBusyGap)")
        // Every overtaken run (hanging ones included) was stopped.
        #expect(try await scripts.processesGone(), "no script, child, or zombie left: \(scripts.pids())")
    }
}

/// The frontmatter each window's file has at each step of `frontmatterOverridesDuringReloads`.
struct OverridePlan {
    let themes: [String]
    let flavors: [String]
    let steps = 30

    /// The theme the second window's reader picks (and keeps).
    var pickInSecondWindow: String { themes[2 % themes.count] }

    func theme(step: Int, index: Int) -> String { themes[(step + index) % themes.count] }

    func flavor(step: Int, index: Int) -> String { flavors[(step * 3 + index) % flavors.count] }

    func source(step: Int, index: Int) -> String {
        StressTests.overrideSource(
            step: step, index: index, theme: theme(step: step, index: index), flavor: flavor(step: step, index: index))
    }
}
