import AppKit
import Foundation
import Testing
import WebKit

@testable import MdvApp

/// Live reload end to end: a `MarkdownDocument` with a window, its file changed on disk by
/// another process, and the window following along.
@MainActor
@Suite("Live reload", .serialized, .timeLimit(.minutes(1)))
struct LiveReloadTests {
    static let markdownType = "net.daringfireball.markdown"
    /// 200 one-line paragraphs: paragraph N is on line 2N - 1.
    static let longSource = (1...200).map { "Paragraph \($0)." }.joined(separator: "\n\n")

    let folder: URL
    let file: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "mdv-live-reload-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = folder.appending(path: "notes.md")
    }

    /// Opens `source` as a document with a window, once the page has loaded.
    func open(_ source: String) async throws -> (MarkdownDocument, DocumentWindowController) {
        try Data(source.utf8).write(to: file)
        let document = try MarkdownDocument(contentsOf: file, ofType: Self.markdownType)
        document.makeWindowControllers()
        let controller = try #require(document.windowControllers.first as? DocumentWindowController)
        try await until("the first load") { controller.coordinator.hasLoadedPage }
        return (document, controller)
    }

    /// Runs `script` with `/bin/sh` in the test folder, as another app would change the file.
    func shell(_ script: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script]
        process.currentDirectoryURL = folder
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "sh -c \(script)")
    }

    func until(
        _ what: String, timeout: Duration = .seconds(5), _ condition: () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while try await !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("timed out waiting for \(what)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func pageTitle(_ controller: DocumentWindowController) async throws -> String? {
        try await controller.coordinator.webView.callAsyncJavaScript(
            "return document.title;", arguments: [:], in: nil, contentWorld: AppScripts.world) as? String
    }

    func waitForPageTitle(_ title: String, in controller: DocumentWindowController) async throws {
        try await until("page title \(title)") { try await pageTitle(controller) == title }
    }

    // MARK: Reloading

    @Test("an atomic save from another process updates the document and the page")
    func reloadsOnSave() async throws {
        let (document, controller) = try await open("# First")
        defer { document.close() }
        try shell("printf '# Second\\n' > .tmp && mv .tmp notes.md")
        try await waitForPageTitle("Second", in: controller)
        #expect(document.content?.source == "# Second\n")
        #expect(controller.window?.title == "Second")
        #expect(document.fileStatus == .current)
    }

    @Test("keeps the reading position across a reload")
    func keepsPosition() async throws {
        let (document, controller) = try await open(Self.longSource)
        defer { document.close() }
        try await controller.coordinator.scroll(toSourceLine: 101)
        try shell("echo '\n# Appended' >> notes.md")
        try await waitForPageTitle("Appended", in: controller)
        let line = try await controller.coordinator.currentSourceLine()
        #expect(abs(line - 101) < 0.05, "top line \(line)")
    }

    @Test("after the web content process exits, the page loads again at the reading position (#43)")
    func recoversFromCrash() async throws {
        let (document, controller) = try await open(Self.longSource)
        defer { document.close() }
        let coordinator = controller.coordinator
        try await coordinator.scroll(toSourceLine: 101)
        try await until("the position reported") { abs((controller.lastSourceLine ?? 0) - 101) < 0.05 }
        // What WebKit calls when the process crashes; the dead page can't report its position.
        coordinator.webViewWebContentProcessDidTerminate(coordinator.webView)
        #expect(!coordinator.hasLoadedPage)
        try await until("the page loaded again") { coordinator.hasLoadedPage }
        try await until("the reading position restored") {
            abs(try await coordinator.currentSourceLine() - 101) < 0.05
        }
    }

    @Test("stays at the bottom while the file grows")
    func followsTail() async throws {
        let (document, controller) = try await open(Self.longSource)
        defer { document.close() }
        try await controller.coordinator.callBridge(
            "window.scrollTo(0, document.documentElement.scrollHeight); return true;")
        for index in 1...3 {
            try shell("echo '\n# Tail \(index)' >> notes.md")
            try await until("tail \(index) rendered") { document.content?.source.contains("Tail \(index)") == true }
            try await until("at the bottom after tail \(index)") {
                try await controller.coordinator.readingPosition().atBottom
            }
        }
    }

    @Test("invalid UTF-8 keeps the last render and shows an error; a fix recovers")
    func invalidUTF8() async throws {
        let (document, controller) = try await open("# Good")
        defer { document.close() }
        try shell("printf '\\377\\376\\375' > notes.md")
        try await until("unreadable status") {
            if case .unreadable = document.fileStatus { true } else { false }
        }
        #expect(document.content?.source == "# Good")
        #expect(try await pageTitle(controller) == "Good")

        try shell("printf '# Fixed\\n' > notes.md")
        try await waitForPageTitle("Fixed", in: controller)
        #expect(document.fileStatus == .current)
    }

    @Test("an unreadable file keeps the last render and shows an error")
    func unreadable() async throws {
        let (document, _) = try await open("# Good")
        defer {
            try? shell("chmod 644 notes.md")
            document.close()
        }
        try shell("chmod 000 notes.md && touch notes.md")
        try await until("unreadable status") {
            if case .unreadable = document.fileStatus { true } else { false }
        }
        #expect(document.content?.source == "# Good")
    }

    @Test("delete shows the deleted state and keeps the page; recreate reloads")
    func deleteAndRecreate() async throws {
        let (document, controller) = try await open("# Kept")
        defer { document.close() }
        try shell("rm notes.md")
        try await until("deleted status") { document.fileStatus == .deleted }
        #expect(document.content?.source == "# Kept")
        #expect(try await pageTitle(controller) == "Kept")

        try shell("printf '# Back\\n' > notes.md")
        try await waitForPageTitle("Back", in: controller)
        #expect(document.fileStatus == .current)
    }

    @Test("a rename follows the file: new URL, new fallback title, still watched")
    func rename() async throws {
        let (document, controller) = try await open("no heading")
        defer { document.close() }
        #expect(controller.window?.title == "notes.md")
        try shell("mv notes.md renamed.md")
        try await until("the window title follows") { controller.window?.title == "renamed.md" }
        #expect(document.fileURL?.lastPathComponent == "renamed.md")
        // The title changes as soon as the rename is noticed; the page reloads at the new
        // document URL (new scope for local images) asynchronously after that.
        try await until("the page reloads at the new URL") {
            controller.coordinator.webView.url?.lastPathComponent == "renamed.md"
        }

        try shell("echo '\n# Still watched' >> renamed.md")
        try await waitForPageTitle("Still watched", in: controller)
    }

    @Test("the newest change wins when changes overlap")
    func newestWins() async throws {
        let (document, controller) = try await open("# Start")
        defer { document.close() }
        for index in 1...10 {
            try shell("printf '# Version \(index)\\n' > notes.md")
            try await Task.sleep(for: .milliseconds(Int.random(in: 0...60)))
        }
        try await waitForPageTitle("Version 10", in: controller)
        try await Task.sleep(for: .milliseconds(300))
        #expect(try await pageTitle(controller) == "Version 10")
        #expect(document.content?.source == "# Version 10\n")
    }

    @Test("closing the document stops watching")
    func closeStops() async throws {
        let (document, _) = try await open("# Open")
        document.close()
        try shell("printf '# Changed\\n' > notes.md")
        try await Task.sleep(for: .milliseconds(400))
        #expect(document.content?.source == "# Open")
    }

    // MARK: Responsiveness

    /// About 1 MB of mixed Markdown: headings, inline markup, lists, highlighted code, tables.
    nonisolated static func largeSource(marker: String) -> String {
        let section = """
            ## Section NUMBER

            Some *emphasis*, **strong text**, `inline code`, and a [link](https://example.com) in a \
            paragraph that goes on for a while to look like real prose, with enough words to wrap.

            - first item with `code`
            - second item
              - nested item

            ```swift
            func section(_ number: Int) -> String {
                let values = (1...number).map { "\\($0)" }
                return values.joined(separator: ", ")
            }
            ```

            | Column | Value |
            | ------ | ----- |
            | a      | 1     |
            | b      | 2     |


            """
        var source = "# \(marker)\n\n"
        var number = 1
        while source.utf8.count < 1_000_000 {
            source += section.replacingOccurrences(of: "NUMBER", with: "\(number)")
            number += 1
        }
        return source
    }

    @Test("reloading a 1 MB document doesn't stall the main thread")
    func largeDocumentStaysResponsive() async throws {
        let (document, controller) = try await open(Self.largeSource(marker: "Before"))
        defer { document.close() }
        try await controller.coordinator.scroll(toSourceLine: 5000)

        // A main-actor heartbeat: the longest gap between ticks is the longest stall.
        let heartbeat = Heartbeat()
        let ticking = Task { await heartbeat.run() }
        try Data(Self.largeSource(marker: "After").utf8).write(to: file)
        try await until("the 1 MB page swapped", timeout: .seconds(20)) {
            try await pageTitle(controller) == "After"
        }
        heartbeat.stop()
        await ticking.value
        let line = try await controller.coordinator.currentSourceLine()
        #expect(abs(line - 5000) < 2, "top line \(line)")
        // Issue budget: no main-thread stall over ~100 ms. Measured locally: see the #21 notes.
        #expect(heartbeat.longestGap < .milliseconds(100), "longest main-thread gap \(heartbeat.longestGap)")
    }
}

/// Ticks on the main actor every few milliseconds and records the longest gap between ticks.
@MainActor
final class Heartbeat {
    private(set) var longestGap: Duration = .zero
    private var isRunning = true

    func run() async {
        var last = ContinuousClock.now
        while isRunning {
            try? await Task.sleep(for: .milliseconds(2))
            let now = ContinuousClock.now
            longestGap = max(longestGap, now - last)
            last = now
        }
    }

    func stop() {
        isRunning = false
    }
}
