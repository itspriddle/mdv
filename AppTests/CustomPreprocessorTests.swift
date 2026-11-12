import AppKit
import Foundation
import PeepCore
import Testing

@testable import PeepApp

/// The custom preprocessor in the app (#57): the store is off by default and distrusts stored
/// values, Settings turns it on only through the warning, documents run it on open and on every
/// live reload, a failure renders the document without it (with the reason for the bar), and
/// changing it re-renders open documents. Scripts are written per test (`PreprocessorScripts`).
@MainActor
@Suite("Custom preprocessor", .serialized, .timeLimit(.minutes(2)))
final class CustomPreprocessorTests: DocumentWindowTestCase {
    var scripts: PreprocessorScripts { PreprocessorScripts(folder: folder) }

    func store(isPersistent: Bool = true) -> CustomPreprocessorSettings {
        CustomPreprocessorSettings(defaults: defaults, isPersistent: isPersistent)
    }

    func store(running executable: String, arguments: [String] = []) -> CustomPreprocessorSettings {
        PreprocessorScripts.settings(running: executable, arguments: arguments, defaults: defaults)
    }

    func bodyText(_ controller: DocumentWindowController) async throws -> String {
        try await controller.coordinator.webView.callAsyncJavaScript(
            "return document.querySelector('.markdown-body').textContent;", arguments: [:], in: nil,
            contentWorld: AppScripts.world) as? String ?? ""
    }

    // MARK: Documents

    @Test("an open document renders the preprocessor's output; Copy as HTML copies it")
    func runsOnOpen() async throws {
        defer { closeAll() }
        let store = store(running: try scripts.upcase())
        let (document, controller) = try await open("# Hello\n\nSome text.\n", customPreprocessorSettings: store)
        try await until("the processed page") { try await bodyText(controller).contains("SOME TEXT.") }
        let content = try #require(document.content)
        #expect(content.source == "# Hello\n\nSome text.\n", "the file's text is kept")
        #expect(content.renderedSource == "# HELLO\n\nSOME TEXT.\n")
        #expect(content.preprocessorError == nil)
        #expect(content.page.title == "HELLO")
        #expect(store.lastRun?.documentName == "notes.md")
        #expect(store.lastRun?.error == nil)

        await controller.writeHTML(to: pasteboard)
        #expect(pasteboard.string(forType: .html)?.contains("SOME TEXT.") == true)
        controller.writeMarkdownSource(to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "# Hello\n\nSome text.\n", "the source is the file's")
    }

    @Test("arguments are passed verbatim and the path goes in PEEP_DOCUMENT_PATH")
    func argumentsAndPath() async throws {
        defer { closeAll() }
        let arguments = ["--flag", "two words", "$HOME", "; rm -rf /"]
        let store = store(running: try scripts.report(), arguments: arguments)
        let (document, controller) = try await open("# Report\n", name: "report.md", customPreprocessorSettings: store)
        try await until("the report") { try await bodyText(controller).contains("path:") }
        let text = try await bodyText(controller)
        for argument in arguments {
            #expect(text.contains("arg:\(argument)\n"), "\(argument)")
        }
        let path = try #require(document.fileURL).path(percentEncoded: false)
        #expect(text.contains("path:\(path)"))
    }

    @Test("a failing script renders the document without it and reports why")
    func failureRendersUnprocessed() async throws {
        defer { closeAll() }
        let store = store(running: try scripts.fail(stderr: "line 7: bad input"))
        let (document, controller) = try await open("# Plain\n\nUnprocessed text.\n", customPreprocessorSettings: store)
        let content = try #require(document.content)
        let error = try #require(content.preprocessorError)
        #expect(error.reason == .exited(status: 3))
        #expect(error.standardError.contains("line 7: bad input"))
        #expect(content.renderedSource == content.source)
        #expect(try await bodyText(controller).contains("Unprocessed text."))
        #expect(store.lastRun?.error == error)
    }

    @Test("a program deleted after it was chosen is a failure, not a silent unprocessed render")
    func executableGone() async throws {
        defer { closeAll() }
        let script = try scripts.upcase()
        let store = store(running: script)
        try FileManager.default.removeItem(atPath: script)
        let (document, _) = try await open("# Plain\n", customPreprocessorSettings: store)
        let error = try #require(document.content?.preprocessorError)
        #expect(error.reason == .executableUnavailable(.notFound(script)))
    }

    @Test("a live reload runs it again")
    func liveReloadReruns() async throws {
        defer { closeAll() }
        let store = store(running: try scripts.upcase())
        let (document, controller) = try await open("first version\n", customPreprocessorSettings: store)
        document.startLiveReload()
        try await until("the first render") { try await bodyText(controller).contains("FIRST VERSION") }
        try Data("second version\n".utf8).write(to: try #require(document.fileURL))
        try await until("the reload") { try await bodyText(controller).contains("SECOND VERSION") }
        #expect(document.content?.source == "second version\n")
    }

    @Test("turning it off, changing the program, or its arguments re-renders open documents in place")
    func settingsReRender() async throws {
        defer { closeAll() }
        let store = store(running: try scripts.upcase())
        let (document, controller) = try await open("Mixed Case.\n", customPreprocessorSettings: store)
        try await until("the processed page") { try await bodyText(controller).contains("MIXED CASE.") }
        _ = try await controller.coordinator.webView.callAsyncJavaScript(
            "window.peepPreprocessorMarker = 7; return true;", arguments: [:], in: nil, contentWorld: AppScripts.world)

        store.isEnabled = false
        try await until("the unprocessed page") { try await bodyText(controller).contains("Mixed Case.") }
        #expect(document.content?.preferences.customPreprocessor == nil)
        let marker = try await controller.coordinator.webView.callAsyncJavaScript(
            "return window.peepPreprocessorMarker;", arguments: [:], in: nil, contentWorld: AppScripts.world)
        #expect(marker as? Int == 7, "swapped in place, no reload")

        store.executablePath = try scripts.report()
        store.isEnabled = true
        try await until("the new program's output") { try await bodyText(controller).contains("path:") }

        store.arguments = ["--new"]
        try await until("the new arguments") { try await bodyText(controller).contains("arg:--new") }
    }

    @Test("turning a hanging script off renders at once instead of waiting for its timeout")
    func disablingDuringRun() async throws {
        defer { closeAll() }
        let store = store(running: try scripts.hang())
        let file = folder.appending(path: "hang.md")
        try Data("# Waiting\n".utf8).write(to: file)
        let document = try MarkdownDocument(contentsOf: file, ofType: Self.markdownType)
        document.customPreprocessorSettings = store
        documents.append(document)
        try await until("the script starts") { !scripts.pids().isEmpty }

        let start = ContinuousClock.now
        store.isEnabled = false
        try await until("the unprocessed render") { document.content != nil }
        #expect(ContinuousClock.now - start < .seconds(2), "didn't wait for the 5 s timeout")
        #expect(document.content?.preprocessorError == nil)
        #expect(try await scripts.processesGone())
    }

    @Test("closing a document stops its script's process group")
    func closeStopsScript() async throws {
        let store = store(running: try scripts.hang())
        let file = folder.appending(path: "close.md")
        try Data("# Closing\n".utf8).write(to: file)
        let document = try MarkdownDocument(contentsOf: file, ofType: Self.markdownType)
        document.customPreprocessorSettings = store
        try await until("the script starts") { !scripts.pids().isEmpty }
        document.close()
        #expect(document.pendingRender == nil)
        #expect(try await scripts.processesGone())
        #expect(document.content == nil, "the cancelled run shows nothing")
    }

    @Test("frontmatter can't turn it on or choose a program")
    func frontmatterCantEnable() async throws {
        defer { closeAll() }
        let marker = folder.appending(path: "ran")
        let script = try scripts.write("marker.sh", "touch '\(marker.path(percentEncoded: false))'\ncat")
        let source = """
            ---
            peep:
              preprocessor: \(script)
              customPreprocessor: \(script)
              customPreprocessorEnabled: true
            CustomPreprocessorEnabled: true
            CustomPreprocessorExecutable: \(script)
            ---
            # Untrusted
            """
        // The app's own (off) store, as every document starts.
        let (document, controller) = try await open(source)
        #expect(try await bodyText(controller).contains("Untrusted"))
        #expect(document.content?.preferences.customPreprocessor == nil)
        #expect(document.content?.preprocessorError == nil)
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
        #expect(!CustomPreprocessorSettings.shared.isEnabled)
        #expect(CustomPreprocessorSettings.shared.executablePath == nil)
    }
}
