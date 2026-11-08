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
        // Measured from here: opening the windows above is the test's own main-thread work.
        let heartbeat = MainThreadHeartbeat()
        heartbeat.start()
        defer { heartbeat.stop() }
        // The hanging scripts take the whole timeout plus the grace period (5.5 s).
        for (script, (document, controller)) in windows {
            try await until("\(script.name) loads", timeout: .seconds(20)) { controller.coordinator.hasLoadedPage }
            let content = try #require(document.content)
            #expect(content.preprocessorError?.reason.kindName == script.failure, "\(script.name)")
            #expect(try await bodyText(controller).contains("Body of \(script.name)."), "\(script.name)")
        }
        #expect(heartbeat.longestBusyGap < .milliseconds(150), "main thread busy \(heartbeat.longestBusyGap)")
        #expect(heartbeat.longestGap < .milliseconds(500), "longest main-thread gap \(heartbeat.longestGap)")
        #expect(try await scripts.processesGone(), "no script, child, or zombie left: \(scripts.pids())")
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
        let heartbeat = MainThreadHeartbeat()
        heartbeat.start()
        defer { heartbeat.stop() }
        weak var lastDocument: MarkdownDocument?
        for round in 0..<3 {
            for index in 0..<6 {
                let url = try write("# Closing \(index)", to: "closing-\(round)-\(index).md")
                let (document, _) = try open(url, preprocessor: index.isMultiple(of: 2) ? hang : fork)
                // Close at once, after a turn, or once the script is running.
                switch (index + round) % 3 {
                case 0:
                    document.close()
                case 1:
                    await Task.yield()
                    document.close()
                default:
                    try await Task.sleep(for: .milliseconds(150))
                    document.close()
                }
                #expect(document.pendingRender == nil)
                #expect(document.pendingReload == nil)
                lastDocument = document
            }
        }
        #expect(heartbeat.longestBusyGap < .milliseconds(150), "main thread busy \(heartbeat.longestBusyGap)")
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
