import AppKit
import Foundation
import Testing
import WebKit

@testable import MdvApp

/// The M2 crash and hang pass (#27), in process so a failure is a test failure rather than a
/// crash dialog: windows opened, reloaded, and closed faster than their pages load; files
/// deleted, renamed, and rewritten while open; and malformed or non-UTF-8 files. Run under the
/// Address and Thread Sanitizers as well (see docs/ROADMAP.md, M2).
@MainActor
@Suite("Stress", .serialized, .timeLimit(.minutes(2)))
struct StressTests {
    static let markdownType = "net.daringfireball.markdown"

    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "mdv-stress-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func write(_ data: Data, to name: String) throws -> URL {
        let url = folder.appending(path: name)
        try data.write(to: url)
        return url
    }

    func write(_ source: String, to name: String) throws -> URL {
        try write(Data(source.utf8), to: name)
    }

    /// Opens `url` as a document with a window, without waiting for the page.
    func open(_ url: URL) throws -> (MarkdownDocument, DocumentWindowController) {
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        document.makeWindowControllers()
        let controller = try #require(document.windowControllers.first as? DocumentWindowController)
        return (document, controller)
    }

    func until(
        // Generous: a starved CI runner can take over a second per web content process launch,
        // and stress tests open many windows. A wrong end state still fails, just later.
        _ what: String, timeout: Duration = .seconds(30), _ condition: () async throws -> Bool
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

    // MARK: Windows

    @Test("opening and closing many windows before, during, and after their loads")
    func openCloseChurn() async throws {
        let sources = (0..<8).map { index in
            "# Doc \(index)\n\n" + (1...200).map { "Paragraph \($0) of \(index)." }.joined(separator: "\n\n")
        }
        let urls = try sources.enumerated().map { try write($1, to: "doc-\($0).md") }
        for round in 0..<6 {
            var open: [(MarkdownDocument, DocumentWindowController)] = []
            for url in urls {
                let opened = try self.open(url)
                opened.0.showWindows()
                open.append(opened)
            }
            // Close some at once (mid-load), some after a turn, the rest once loaded.
            for (index, (document, controller)) in open.enumerated() {
                switch (index + round) % 3 {
                case 0:
                    document.close()
                case 1:
                    await Task.yield()
                    document.close()
                default:
                    try await until("load \(index)") { controller.coordinator.hasLoadedPage }
                    try await controller.coordinator.scroll(toSourceLine: 100)
                    document.close()
                }
            }
        }
        // The app is still responsive and can open a window normally afterwards.
        let (document, controller) = try open(urls[0])
        defer { document.close() }
        try await until("the final load") { controller.coordinator.hasLoadedPage }
        #expect(try await pageTitle(controller) == "Doc 0")
    }

    @Test("closing windows while their first render is in flight drops the render and frees the document")
    func closeMidRender() async throws {
        let source = FirstRenderTests.largeSource(bytes: 1_000_000)
        let urls = try (0..<6).map { try write(source, to: "large-\($0).md") }
        weak var lastDocument: MarkdownDocument?
        for round in 0..<3 {
            var renders: [Task<Void, Never>] = []
            for (index, url) in urls.enumerated() {
                let (document, controller) = try open(url)
                document.showWindows()
                renders += [document.pendingRender].compactMap { $0 }
                // Close before the render (most), after a turn, or once the page loads.
                switch (index + round) % 3 {
                case 0:
                    document.close()
                case 1:
                    await Task.yield()
                    document.close()
                default:
                    try await until("load \(index)", timeout: .seconds(30)) { controller.coordinator.hasLoadedPage }
                    document.close()
                }
                #expect(document.pendingRender == nil)
                lastDocument = document
            }
            // The dropped renders finish in the background without touching the closed windows.
            for render in renders {
                await render.value
            }
        }
        // Nothing (a render task, the window) keeps the last closed document alive.
        try await until("the closed document is freed") { lastDocument == nil }
        // And a new window still opens and renders normally.
        let (document, controller) = try open(urls[0])
        defer { document.close() }
        try await until("the final load", timeout: .seconds(30)) { controller.coordinator.hasLoadedPage }
        #expect(try await pageTitle(controller) == "Large Document")
    }

    @Test("rapid reloads of many open windows end on the newest content")
    func reloadChurn() async throws {
        let urls = try (0..<5).map { try write("# Start \($0)", to: "reload-\($0).md") }
        let windows = try urls.map(open)
        defer {
            for (document, _) in windows {
                document.close()
            }
        }
        for (_, controller) in windows {
            try await until("first load") { controller.coordinator.hasLoadedPage }
        }
        for step in 1...40 {
            for (index, url) in urls.enumerated() {
                try Data("# Step \(step) of \(index)\n\n\(String(repeating: "word ", count: step * 50))".utf8)
                    .write(to: url)
            }
            if step.isMultiple(of: 7) {
                // Reverts on main interleave with live reloads off main.
                for (document, _) in windows {
                    try document.revert(toContentsOf: try #require(document.fileURL), ofType: Self.markdownType)
                }
            }
            try await Task.sleep(for: .milliseconds(step.isMultiple(of: 5) ? 120 : 5))
        }
        for (index, (document, controller)) in windows.enumerated() {
            try await until("final content \(index)") { try await pageTitle(controller) == "Step 40 of \(index)" }
            #expect(document.fileStatus == .current)
        }
    }

    // MARK: Files changing underneath

    @Test("deleting, renaming, and rewriting files while they are open")
    func fileChurn() async throws {
        let fileManager = FileManager.default
        let urls = try (0..<4).map { try write("# File \($0)", to: "churn-\($0).md") }
        let windows = try urls.map(open)
        defer {
            for (document, _) in windows {
                document.close()
            }
        }
        for (_, controller) in windows {
            try await until("first load") { controller.coordinator.hasLoadedPage }
        }
        for round in 0..<10 {
            for (index, url) in urls.enumerated() {
                let moved = folder.appending(path: "moved-\(index).md")
                switch (index + round) % 4 {
                case 0:
                    try fileManager.removeItem(at: url)
                    try Data("# Back \(round)".utf8).write(to: url)
                case 1:
                    try fileManager.moveItem(at: url, to: moved)
                    try fileManager.moveItem(at: moved, to: url)
                case 2:
                    try Data([0xFF, 0xFE, 0x00]).write(to: url)
                    try Data("# Fixed \(round)".utf8).write(to: url)
                default:
                    try Data().write(to: url)
                }
            }
            try await Task.sleep(for: .milliseconds(round.isMultiple(of: 3) ? 400 : 20))
        }
        // Settle: every file ends with known content at its original path.
        for (index, url) in urls.enumerated() {
            try Data("# Final \(index)".utf8).write(to: url)
        }
        for (index, (document, controller)) in windows.enumerated() {
            try await until("final content \(index)", timeout: .seconds(15)) {
                try await pageTitle(controller) == "Final \(index)"
            }
            #expect(document.fileStatus == .current)
        }
    }

    @Test("a file deleted and its folder removed while open keeps the window and its last render")
    func folderRemoved() async throws {
        let subfolder = folder.appending(path: "gone", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        let url = subfolder.appending(path: "doc.md")
        try Data("# Still Here".utf8).write(to: url)
        let (document, controller) = try open(url)
        defer { document.close() }
        try await until("first load") { controller.coordinator.hasLoadedPage }
        try FileManager.default.removeItem(at: subfolder)
        try await until("the deleted banner") { document.fileStatus == .deleted }
        #expect(try await pageTitle(controller) == "Still Here")
    }

    // MARK: Malformed input

    /// Valid UTF-8 that is hostile to a parser, renderer, or the page.
    nonisolated static let malformedSources: [(String, String)] = [
        ("empty", ""),
        ("NUL bytes", "# Title\u{0}\n\nText\u{0}with\u{0}nuls\n"),
        ("BOM and CR line endings", "\u{FEFF}# Title\r\rLine one\rLine two\r"),
        ("deep block quotes", String(repeating: ">", count: 5_000) + " deep\n"),
        ("deep lists", (0..<1_000).map { String(repeating: "  ", count: $0) + "- item" }.joined(separator: "\n")),
        (
            "deep inline nesting",
            String(repeating: "*_[", count: 5_000) + "x" + String(repeating: "](u)_*", count: 5_000)
        ),
        ("unclosed HTML", String(repeating: "<div><span><table><tr><td>", count: 2_000)),
        ("long line", String(repeating: "word ", count: 400_000)),
        ("many backticks", String(repeating: "`", count: 100_000)),
        ("many links", (0..<20_000).map { "[l\($0)](#h\($0))" }.joined(separator: " ")),
        ("many headings", (0..<5_000).map { "## H\($0 % 7)" }.joined(separator: "\n")),
        ("lone surrogates escaped", "&#xD800; &#xDFFF; &#0; &#x110000; &#99999999999;"),
        ("control characters", String((1..<32).map { Character(UnicodeScalar(UInt8($0))) })),
        ("combining marks", "e" + String(repeating: "\u{0301}", count: 50_000)),
        ("script and handlers", "<script>alert(1)</script><img src=x onerror=alert(1)>[x](javascript:alert(1))"),
    ]

    @Test("malformed but valid UTF-8 files open, render, and live reload", arguments: Self.malformedSources.indices)
    func malformed(index: Int) async throws {
        let (name, source) = Self.malformedSources[index]
        let url = try write(source, to: "malformed-\(index).md")
        let (document, controller) = try open(url)
        defer { document.close() }
        try await until("the load of \(name)", timeout: .seconds(30)) { controller.coordinator.hasLoadedPage }
        #expect(document.content != nil)
        try Data("# Reloaded".utf8).write(to: url)
        try await until("the reload of \(name)", timeout: .seconds(30)) {
            try await pageTitle(controller) == "Reloaded"
        }
    }

    /// Bytes that aren't UTF-8.
    nonisolated static let invalidData: [(String, [UInt8])] = [
        ("lone continuation byte", [0x23, 0x20, 0x80, 0x0A]),
        ("truncated sequence", [0x23, 0x20, 0xE2, 0x82]),
        ("overlong encoding", [0xC0, 0xAF]),
        ("UTF-16 with BOM", [0xFF, 0xFE, 0x23, 0x00, 0x20, 0x00, 0x41, 0x00]),
        ("encoded surrogate", [0xED, 0xA0, 0x80]),
        ("beyond U+10FFFF", [0xF4, 0x90, 0x80, 0x80]),
        ("random bytes", [0xFF] + (0..<4096).map { UInt8(truncatingIfNeeded: ($0 &* 2_654_435_761) >> 13) }),
    ]

    @Test(
        "files that aren't UTF-8 fail to open; a reload to one keeps the last render",
        arguments: Self.invalidData.indices)
    func invalidUTF8(index: Int) async throws {
        let (name, bytes) = Self.invalidData[index]
        let bad = try write(Data(bytes), to: "invalid-\(index).md")
        #expect(throws: (any Error).self, "\(name)") {
            _ = try MarkdownDocument(contentsOf: bad, ofType: Self.markdownType)
        }
        let url = try write("# Good", to: "becomes-invalid-\(index).md")
        let (document, controller) = try open(url)
        defer { document.close() }
        try await until("first load") { controller.coordinator.hasLoadedPage }
        try Data(bytes).write(to: url)
        try await until("the unreadable banner for \(name)") {
            if case .unreadable = document.fileStatus { true } else { false }
        }
        #expect(try await pageTitle(controller) == "Good")
    }
}

extension StressTests {
    @Test("closing windows that were on screen frees their documents and web views")
    func closeShownWindows() async throws {
        let urls = try (0..<3).map { try write("# Shown \($0)\n\nBody \($0).\n", to: "shown-\($0).md") }
        var documents: [WeakBox<MarkdownDocument>] = []
        var coordinators: [WeakBox<WebViewCoordinator>] = []
        for url in urls {
            let (document, controller) = try open(url)
            document.showWindows()
            try await until("load", timeout: .seconds(30)) { controller.coordinator.hasLoadedPage }
            // On screen for a while: AppKit can then keep the closed window itself alive for
            // minutes (seen in the hosted tests), so the window must not keep its content alive.
            try await Task.sleep(for: .milliseconds(500))
            documents.append(WeakBox(document))
            coordinators.append(WeakBox(controller.coordinator))
            document.close()
        }
        try await until("the closed documents are freed") { documents.allSatisfy { $0.value == nil } }
        // The web views (and their web content processes) go with them.
        try await until("the closed windows' web views are freed") { coordinators.allSatisfy { $0.value == nil } }
    }
}

/// A weak reference, for checking that closed windows' objects are freed.
@MainActor
final class WeakBox<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value) {
        self.value = value
    }
}
