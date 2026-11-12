import AppKit
import Foundation
import PeepCore
import Testing

@testable import PeepApp

/// `peep FILE` through Launch Services (#67, #69): the app gets a standard Open Documents event
/// carrying Peep's parameters. AppKit handles it itself (it never calls the delegate's
/// `application(_:open:)` for Peep's document types) and may open its files after the event,
/// so `OpenDocumentsEventTap` records the parameters as the event arrives and
/// `DocumentController` applies them to each file (`OpenDocumentsEventLog`).
@MainActor
@Suite("Open Documents events keep Peep's parameters", .serialized, .timeLimit(.minutes(1)))
final class OpenDocumentsEventTests {
    let folder: URL
    var opened: [NSDocument] = []

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-odoc-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A document whose frontmatter names Serif, so a window showing GitHub got the pick.
    func file(_ name: String) throws -> URL {
        let url = folder.appending(path: name)
        try Data("---\npeep:\n  theme: serif\n---\n# \(name)\n".utf8).write(to: url)
        return url
    }

    var controller: DocumentController {
        get throws { try #require(NSDocumentController.shared as? DocumentController) }
    }

    var opener: DocumentOpener {
        get throws { try #require(NSApp.delegate as? AppDelegate).documentOpener }
    }

    func event(_ files: [URL], _ parameters: AppOpenParameters) -> NSAppleEventDescriptor {
        AppOpenEvent.make(files: files, parameters: parameters, target: NSAppleEventDescriptor.currentProcess())
    }

    /// Waits until every file in `urls` has a window, and returns their window controllers.
    func windows(for urls: [URL]) async throws -> [DocumentWindowController] {
        let deadline = Date.now.addingTimeInterval(10)
        while urls.contains(where: { NSDocumentController.shared.document(for: $0)?.windowControllers.isEmpty ?? true }
        ),
            Date.now < deadline
        {
            try await Task.sleep(for: .milliseconds(20))
        }
        return try urls.map { url in
            let document = try #require(NSDocumentController.shared.document(for: url))
            if !opened.contains(where: { $0 === document }) {
                opened.append(document)
            }
            return try #require(document.windowControllers.first as? DocumentWindowController)
        }
    }

    /// Opens `url` as AppKit does for an Open Documents event's file (display: true), outside
    /// the event, as when an earlier open was still in flight.
    func openAsAppKit(_ url: URL) async throws -> DocumentWindowController {
        let controller = try controller
        await withCheckedContinuation { continuation in
            controller.openDocument(withContentsOf: url, display: true) { _, _, _ in
                continuation.resume()
            }
        }
        return try #require(try await windows(for: [url]).first)
    }

    func closeAll() {
        for document in opened {
            document.close()
        }
        opened.removeAll()
    }

    @Test("the tap is in front of AppKit's Open Documents handler")
    func installed() {
        #expect(OpenDocumentsEventTap.isInstalled)
    }

    /// The whole path: the Apple Event Manager's handler for `aevt/odoc` (the tap, then
    /// AppKit's), as Launch Services' delivery calls it.
    @Test("an event through AppKit's handler opens its files with --theme and --wait")
    func throughAppKit() async throws {
        defer { closeAll() }
        let urls = [try file("a.md"), try file("b.md")]
        let token = UUID()
        let event = event(urls, AppOpenParameters(themeID: "github", waitToken: token))
        var handler: AEEventHandlerUPP?
        var refcon: UnsafeMutableRawPointer?
        let found = AEGetEventHandler(
            AEEventClass(kCoreEventClass), AEEventID(kAEOpenDocuments), &handler, &refcon, false)
        #expect(found == noErr)
        let reply = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEAnswer), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        let installed = try #require(handler)
        let eventDesc = try #require(event.aeDesc)
        let replyDesc = try #require(reply.aeDesc)
        #expect(installed(eventDesc, UnsafeMutablePointer(mutating: replyDesc), refcon) == noErr)

        let controllers = try await windows(for: urls)
        for controller in controllers {
            #expect(controller.pickedThemeID == "github")
            #expect(controller.theme.id == "github")
            #expect(controller.window?.isVisible == true)
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(try opener.waits.pendingTokens.contains(token))
        for controller in controllers {
            controller.window?.close()
        }
        #expect(try !opener.waits.pendingTokens.contains(token))
        #expect(try controller.eventLog.isEmpty)
    }

    @Test("a file AppKit opens after its event still gets the event's parameters, once")
    func afterTheEvent() async throws {
        defer { closeAll() }
        let url = try file("later.md")
        try controller.eventLog.record(event([url], AppOpenParameters(themeID: "github")))
        let window = try await openAsAppKit(url)
        #expect(window.pickedThemeID == "github")
        #expect(try controller.eventLog.isEmpty)

        closeAll()
        let again = try await openAsAppKit(url)
        #expect(again.pickedThemeID == nil, "a later open doesn't inherit the parameters")
    }

    @Test("an already-open file switches to the theme and stays one window")
    func alreadyOpen() async throws {
        defer { closeAll() }
        let url = try file("open.md")
        let first = try await openAsAppKit(url)
        #expect(first.pickedThemeID == nil)
        try controller.eventLog.record(event([url], AppOpenParameters(themeID: "github")))
        let second = try await openAsAppKit(url)
        #expect(first === second)
        #expect(first.pickedThemeID == "github")
        #expect(NSDocumentController.shared.documents.filter { $0.fileURL == url }.count == 1)
    }

    @Test("parameters match the file however its path is spelled")
    func spelling() throws {
        let url = try file("spelled.md")
        let log = OpenDocumentsEventLog()
        log.record(event([url], AppOpenParameters(themeID: "github")))
        // The temp folder is under /var, a symbolic link to /private/var.
        let other = URL(filePath: url.resolvingSymlinksInPath().path(percentEncoded: false))
        #expect(log.take(for: try file("unrelated.md")) == nil)
        #expect(log.take(for: other)?.themeID == "github")
        #expect(log.take(for: url) == nil)
    }

    @Test("events without Peep's parameters, and other events, aren't recorded")
    func notRecorded() throws {
        let url = try file("plain.md")
        let log = OpenDocumentsEventLog()
        log.record(event([url], AppOpenParameters()))
        log.record(
            AppOpenEvent.make(
                files: [url], parameters: AppOpenParameters(themeID: "github"),
                target: NSAppleEventDescriptor.currentProcess(), kind: .direct))
        #expect(log.isEmpty)
    }
}
