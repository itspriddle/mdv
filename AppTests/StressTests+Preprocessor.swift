import AppKit
import Foundation
import MdvCore
import Testing
import WebKit

@testable import MdvApp

/// The custom preprocessor under load (#57, the M4 exit criterion): windows open on scripts
/// that hang, crash, flood stdout, or leave children behind; live reload storms while scripts
/// run; windows closed mid-run. The main thread never stalls (`MainThreadHeartbeat`), every
/// window ends showing something (the output, or the document without it and a reason), and no
/// process is left afterwards.
extension StressTests {
    /// Opens `url` in a window that runs the custom preprocessor from `settings` and live
    /// reloads, as `makeWindowControllers()` does, without waiting for the page.
    func open(_ url: URL, preprocessor settings: CustomPreprocessorSettings) throws -> (
        MarkdownDocument, DocumentWindowController
    ) {
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        document.customPreprocessorSettings = settings
        document.makeWindowControllers()
        document.showWindows()
        let controller = try #require(document.windowControllers.first as? DocumentWindowController)
        return (document, controller)
    }

    func bodyText(_ controller: DocumentWindowController) async throws -> String {
        try await controller.coordinator.webView.callAsyncJavaScript(
            "return document.querySelector('.markdown-body')?.textContent ?? '';", arguments: [:], in: nil,
            contentWorld: AppScripts.world) as? String ?? ""
    }

    @Test("scripts that hang, crash, flood, or fork can't stall the app or leave processes behind")
    func misbehavingPreprocessors() async throws {
        let defaults = try ThrowawayDefaults("mdv-stress")
        let scripts = PreprocessorScripts(folder: folder)
        let cases = [
            MisbehavingScript(name: "hang", path: try scripts.hang(), failure: "timedOut"),
            MisbehavingScript(name: "crash", path: try scripts.crash(), failure: "signaled"),
            MisbehavingScript(name: "flood", path: try scripts.flood(), failure: "outputTooLarge"),
            MisbehavingScript(name: "fork", path: try scripts.fork(), failure: nil),
        ]
        var windows: [(script: MisbehavingScript, window: (MarkdownDocument, DocumentWindowController))] = []
        for script in cases {
            let settings = PreprocessorScripts.settings(running: script.path, defaults: defaults.defaults)
            for index in 0..<3 {
                let name = script.name
                let url = try write("# \(name) \(index)\n\nBody of \(name).\n", to: "\(name)-\(index).md")
                windows.append((script, try open(url, preprocessor: settings)))
            }
        }
        defer {
            for (_, (document, _)) in windows {
                document.close()
            }
        }
        // First renders: each window waits for its script, then loads the page without it (or
        // with the forking script's output). Not timed: starting twelve web content processes
        // at once stalls the main thread for seconds on a slow CI runner (WebKit's launch, not
        // the scripts; #59), which says nothing about the preprocessor.
        // The hanging scripts take the whole timeout plus the grace period (5.5 s).
        for (script, (document, controller)) in windows {
            try await until("\(script.name) loads", timeout: .seconds(20)) { controller.coordinator.hasLoadedPage }
            try await expectRendered(script, version: "", in: (document, controller))
        }
        #expect(try await scripts.processesGone(), "no script, child, or zombie left: \(scripts.pids())")

        // Timed: every script runs again on a live reload while the windows are up, and each
        // window swaps the result in place. The main thread does only the swaps.
        let heartbeat = MainThreadHeartbeat()
        heartbeat.start()
        defer { heartbeat.stop() }
        for (script, (document, _)) in windows {
            let url = try #require(document.fileURL)
            try Data("# \(script.name) again\n\nBody of \(script.name) v2.\n".utf8).write(to: url)
        }
        for (script, window) in windows {
            try await until("\(script.name) reloads", timeout: .seconds(20)) {
                try await bodyText(window.1).contains("Body of \(script.name) v2.") && !window.0.isRendering
            }
            try await expectRendered(script, version: " v2", in: window)
        }
        #expect(heartbeat.longestBusyGap < .milliseconds(150), "main thread busy \(heartbeat.longestBusyGap)")
        #expect(heartbeat.longestGap < .milliseconds(500), "longest main-thread gap \(heartbeat.longestGap)")
        #expect(try await scripts.processesGone(), "no script, child, or zombie left: \(scripts.pids())")
    }

    /// Checks that `window` shows the document (without the script's output on a failure) and
    /// the failure `script` should earn.
    func expectRendered(
        _ script: MisbehavingScript, version: String, in window: (MarkdownDocument, DocumentWindowController)
    ) async throws {
        let content = try #require(window.0.content)
        #expect(content.preprocessorError?.reason.kindName == script.failure, "\(script.name)")
        #expect(try await bodyText(window.1).contains("Body of \(script.name)\(version)."), "\(script.name)")
    }

    @Test("live reload storms while a slow script runs end on the newest content, with no stale runs left")
    func preprocessorReloadStorm() async throws {
        let defaults = try ThrowawayDefaults("mdv-stress")
        let scripts = PreprocessorScripts(folder: folder)
        let settings = PreprocessorScripts.settings(
            running: try scripts.slow(seconds: 0.3), defaults: defaults.defaults)
        let urls = try (0..<4).map { try write("# Start \($0)", to: "storm-\($0).md") }
        let windows = try urls.map { try open($0, preprocessor: settings) }
        defer {
            for (document, _) in windows {
                document.close()
            }
        }
        // Timed once the windows are up, as in `misbehavingPreprocessors`.
        for (_, controller) in windows {
            try await until("first load", timeout: .seconds(15)) { controller.coordinator.hasLoadedPage }
        }
        let heartbeat = MainThreadHeartbeat()
        heartbeat.start()
        defer { heartbeat.stop() }
        for step in 1...30 {
            for (index, url) in urls.enumerated() {
                try Data("# Step \(step) of \(index)\n\n\(String(repeating: "word ", count: step * 20))".utf8)
                    .write(to: url)
            }
            try await Task.sleep(for: .milliseconds(step.isMultiple(of: 6) ? 400 : 15))
        }
        for (index, (document, controller)) in windows.enumerated() {
            try await until("final content \(index)", timeout: .seconds(15)) {
                try await pageTitle(controller) == "Step 30 of \(index)"
            }
            #expect(document.fileStatus == .current)
            #expect(document.content?.preprocessorError == nil)
        }
        #expect(heartbeat.longestBusyGap < .milliseconds(150), "main thread busy \(heartbeat.longestBusyGap)")
        // Every overtaken run was cancelled: nothing is still running a stale version.
        #expect(try await scripts.processesGone())
    }

    @Test("closing windows while their scripts run stops every script and frees the documents")
    func closeMidPreprocessor() async throws {
        let defaults = try ThrowawayDefaults("mdv-stress")
        let scripts = PreprocessorScripts(folder: folder)
        let hang = PreprocessorScripts.settings(running: try scripts.hang(), defaults: defaults.defaults)
        let fork = PreprocessorScripts.settings(running: try scripts.fork(), defaults: defaults.defaults)
        weak var lastDocument: MarkdownDocument?
        // Each close is timed on its own, not with a heartbeat: opening 18 windows (and starting
        // their web content processes) is the test's own main-thread work, seconds of it on a
        // slow CI runner (#59). A close that waited for its script would take at least the
        // 0.5 s grace period a TERM-ignoring script gets before `SIGKILL`.
        var longestClose = Duration.zero
        for round in 0..<3 {
            for index in 0..<6 {
                let url = try write("# Closing \(index)", to: "closing-\(round)-\(index).md")
                let (document, _) = try open(url, preprocessor: index.isMultiple(of: 2) ? hang : fork)
                // Close at once, after a turn, or once the script is running.
                switch (index + round) % 3 {
                case 0:
                    break
                case 1:
                    await Task.yield()
                default:
                    try await Task.sleep(for: .milliseconds(150))
                }
                longestClose = max(longestClose, ContinuousClock().measure { document.close() })
                #expect(document.pendingRender == nil)
                #expect(document.pendingReload == nil)
                lastDocument = document
            }
        }
        #expect(longestClose < .milliseconds(400), "longest close \(longestClose)")
        #expect(try await scripts.processesGone(), "no script, child, or zombie left: \(scripts.pids())")
        try await until("the closed document is freed") { lastDocument == nil }
    }
}

extension PreprocessorError.Reason {
    /// The case's name without its payload ("timedOut").
    var kindName: String {
        String(describing: self).prefix { $0 != "(" }.description
    }
}

/// A script for `misbehavingPreprocessors`, and the failure it should earn (a
/// `PreprocessorError.Reason` case name), or `nil` for a successful run.
struct MisbehavingScript {
    let name: String
    let path: String
    let failure: String?
}
