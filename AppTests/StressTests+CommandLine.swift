import AppKit
import Foundation
import MdvCore
import Testing

@testable import MdvApp

/// The M5 crash and hang pass (#72): what `mdv` sends the app, driven through `DocumentOpener`
/// as `AppDelegate` drives it, without launching anything. Many `mdv FILE` events at once
/// (files shared between them, standard input among them), `--wait` tokens when the app quits
/// mid-open, the largest standard input the CLI sends, and `--theme` changing while a window's
/// first render is in flight. Run under the Address and Thread Sanitizers as well
/// (docs/ROADMAP.md, M5).
extension StressTests {
    /// An opener over throwaway theme settings that records presented errors and posted tokens.
    @MainActor
    final class CommandLineEvents {
        let opener: DocumentOpener
        private let record: CommandLineEventRecord

        init(defaults: ThrowawayDefaults) {
            let record = CommandLineEventRecord()
            self.record = record
            opener = DocumentOpener(
                themeSettings: ThemeSettings(defaults: defaults.defaults, isPersistent: true),
                waits: WindowWaits(post: { record.posted.append($0) }), presentError: { record.errors.append($0) })
        }

        var errors: [any Error] { record.errors }
        var posted: [UUID] { record.posted }
        var isIdle: Bool { record.inFlight == 0 }

        /// Sends one open event without waiting for it, as a second `mdv` would.
        func send(_ urls: [URL], themeID: String? = nil, waitToken: UUID? = nil) {
            let record = record
            record.inFlight += 1
            opener.open(urls, parameters: AppOpenParameters(themeID: themeID, waitToken: waitToken)) {
                record.inFlight -= 1
            }
        }
    }

    /// Every document `urls` opened, once each, plus the untitled standard input ones.
    func documents(for urls: [URL]) throws -> [MarkdownDocument] {
        try urls.map { url in
            try #require(
                NSDocumentController.shared.document(for: url) as? MarkdownDocument, "\(url.lastPathComponent)")
        }
    }

    var standardInputDocuments: [MarkdownDocument] {
        NSDocumentController.shared.documents.compactMap { $0 as? MarkdownDocument }.filter { $0.fileURL == nil }
    }

    func closeEveryDocument() {
        for document in NSDocumentController.shared.documents {
            document.close()
        }
    }

    @Test("many mdv FILE events at once, sharing files and piping input, open each file once")
    func manyOpenEvents() async throws {
        defer { closeEveryDocument() }
        let defaults = try ThrowawayDefaults("mdv-stress-cli")
        let events = CommandLineEvents(defaults: defaults)
        let urls = try (0..<12).map { try write("# File \($0)\n\nBody \($0).\n", to: "cli-\($0).md") }
        let themes = ["github", "document", "serif"]
        // No main-thread bound here: the windows of events sent this fast come up in one turn of
        // the main queue, as when Finder opens that many files at once (about 0.55 s for ~20
        // windows in Debug, #72). This checks the outcome; the large-input case below is timed.

        // 24 events back to back: each names four files (overlapping the others'), every third
        // also pipes standard input, every other one has a theme. Each is its own turn of the run
        // loop, as separate Apple Events are, and none waits for the one before to finish.
        var handoffs: [URL] = []
        for event in 0..<24 {
            var files = (0..<4).map { urls[(event * 3 + $0) % urls.count] }
            if event.isMultiple(of: 3) {
                let handoff = try StandardInputHandoff.write(Data("# Piped \(event)\n".utf8), inFolder: folder)
                handoffs.append(handoff)
                files.append(handoff)
            }
            events.send(files, themeID: event.isMultiple(of: 2) ? themes[event % themes.count] : nil)
            await Task.yield()
        }
        try await until("every event to finish") { events.isIdle }

        #expect(events.errors.isEmpty, "\(events.errors)")
        let documents = try documents(for: urls)
        for (url, document) in zip(urls, documents) {
            #expect(
                NSDocumentController.shared.documents.filter { $0.fileURL == url }.count == 1,
                "\(url.lastPathComponent)")
            #expect(document.windowControllers.count == 1, "\(url.lastPathComponent)")
            let controller = try #require(document.windowControllers.first as? DocumentWindowController)
            #expect(controller.pickedThemeID.map(themes.contains) ?? true)
        }
        #expect(standardInputDocuments.count == handoffs.count)
        for handoff in handoffs {
            #expect(!FileManager.default.fileExists(atPath: handoff.deletingLastPathComponent().path))
        }
        for document in documents + standardInputDocuments {
            try await until("\(document.displayName) renders") { document.content != nil && !document.isRendering }
        }
    }

    @Test("--wait tokens when the app quits mid-open are each notified exactly once")
    func waitsWhenQuitting() async throws {
        defer { closeEveryDocument() }
        let defaults = try ThrowawayDefaults("mdv-stress-cli")
        let events = CommandLineEvents(defaults: defaults)
        let urls = try (0..<6).map { try write("# Wait \($0)\n", to: "wait-\($0).md") }
        var tokens: [UUID] = []
        // Some events finish opening and some windows close before the quit; others are
        // still opening when it comes.
        for round in 0..<5 {
            for event in 0..<4 {
                let token = UUID()
                tokens.append(token)
                events.send(
                    [urls[(round + event) % urls.count], urls[(round + event + 1) % urls.count]], waitToken: token)
            }
            if round == 1 {
                try await until("the first rounds to open") { events.isIdle }
                NSDocumentController.shared.document(for: urls[1])?.close()
            }
            await Task.yield()
        }
        // What `applicationWillTerminate` does.
        events.opener.waits.notifyAll()
        try await until("every event to finish") { events.isIdle }
        closeEveryDocument()
        // Late events after the quit started still end their own waits.
        let late = UUID()
        events.send([urls[0]], waitToken: late)
        try await until("the late event to open") { events.isIdle }
        closeEveryDocument()

        #expect(events.errors.isEmpty, "\(events.errors)")
        #expect(events.posted.count == Set(events.posted).count, "no token is notified twice")
        #expect(Set(events.posted) == Set(tokens + [late]))
        #expect(events.opener.waits.pendingTokens.isEmpty)
    }

    @Test("the largest standard input mdv sends opens in a window; one byte more is refused")
    func largestStandardInput() async throws {
        defer { closeEveryDocument() }
        let defaults = try ThrowawayDefaults("mdv-stress-cli")
        let events = CommandLineEvents(defaults: defaults)
        // Ordinary Markdown up to just under the cap, then one long paragraph to land on it.
        var source = FirstRenderTests.largeSource(bytes: StandardInputHandoff.maximumBytes - 100_000) + "\n"
        source += String(repeating: "x", count: StandardInputHandoff.maximumBytes - source.utf8.count)
        #expect(source.utf8.count == StandardInputHandoff.maximumBytes)
        let largest = try StandardInputHandoff.write(Data(source.utf8), inFolder: folder)
        let tooLarge = try StandardInputHandoff.write(Data((source + "x").utf8), inFolder: folder)
        let token = UUID()

        let heartbeat = MainThreadHeartbeat()
        heartbeat.start()
        defer { heartbeat.stop() }
        events.send([largest, tooLarge], themeID: "serif", waitToken: token)
        try await until("the event to finish") { events.isIdle }
        let document = try #require(standardInputDocuments.first)
        #expect(standardInputDocuments.count == 1)
        try await until("the large window renders", timeout: .seconds(90)) {
            document.content != nil && !document.isRendering
        }
        heartbeat.stop()

        #expect(document.content?.source.utf8.count == StandardInputHandoff.maximumBytes)
        #expect(events.errors.compactMap { $0 as? StandardInputHandoff.Failure } == [.tooLarge])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty, "both handoffs are gone")
        let controller = try #require(document.windowControllers.first as? DocumentWindowController)
        #expect(controller.pickedThemeID == "serif")
        // Reading and decoding happen on main (as for a file); rendering doesn't.
        expectTiming(heartbeat.longestBusyGap < .milliseconds(500), "main thread busy \(heartbeat.longestBusyGap)")
        document.close()
        #expect(events.posted == [token])
    }

    @Test("--theme changing while a window's first render is in flight ends on the last theme")
    func themeChangesDuringRender() async throws {
        defer { closeEveryDocument() }
        let defaults = try ThrowawayDefaults("mdv-stress-cli")
        let events = CommandLineEvents(defaults: defaults)
        let registry = ThemeRegistry.bundled
        let themes = registry.themes.map(\.id)
        let urls = try (0..<3).map {
            try write(FirstRenderTests.largeSource(bytes: 300_000 * ($0 + 1)), to: "render-\($0).md")
        }
        // Each step re-sends every file with the next theme, as repeated `mdv --theme X FILE`
        // would, while the first renders (and the theme swaps before them) are still going.
        let steps = 12
        for step in 0..<steps {
            for (index, url) in urls.enumerated() {
                events.send([url], themeID: themes[(step + index) % themes.count])
            }
            if step.isMultiple(of: 3) { await Task.yield() }
        }
        try await until("every event to finish") { events.isIdle }

        #expect(events.errors.isEmpty, "\(events.errors)")
        for (index, document) in try documents(for: urls).enumerated() {
            let last = themes[(steps - 1 + index) % themes.count]
            let controller = try #require(document.windowControllers.first as? DocumentWindowController)
            #expect(document.windowControllers.count == 1)
            #expect(controller.pickedThemeID == last, "window \(index)")
            try await until("window \(index)'s first page") { controller.coordinator.hasLoadedPage }
            try await untilShowing(registry.theme(id: last), in: controller, "window \(index)")
        }
    }
}

/// What `StressTests.CommandLineEvents` saw: presented errors, posted tokens, events in flight.
@MainActor
final class CommandLineEventRecord {
    var errors: [any Error] = []
    var posted: [UUID] = []
    var inFlight = 0
}
