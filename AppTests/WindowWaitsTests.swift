import AppKit
import Foundation
import PeepCore
import Testing

@testable import PeepApp

/// `peep --wait` in the app (#69): `WindowWaits` notifies a token once every window opened for it
/// has closed, and `DocumentOpener` feeds it the windows of an open event with a token.
@MainActor
@Suite("Waiting for windows to close", .serialized, .timeLimit(.minutes(1)))
final class WindowWaitsTests {
    let folder: URL
    let throwawayDefaults: ThrowawayDefaults
    var posted: [UUID] = []
    var opened: [NSDocument] = []

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-waits-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        throwawayDefaults = try ThrowawayDefaults("peep-wait-tests")
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    func waits() -> WindowWaits {
        WindowWaits(post: { [weak self] in self?.posted.append($0) })
    }

    func window() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled, .closable],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    func file(_ name: String) throws -> URL {
        let url = folder.appending(path: name)
        try Data("# \(name)\n".utf8).write(to: url)
        return url
    }

    @Test("a token is notified once its last window closes, not before")
    func lastWindow() {
        let waits = waits()
        let token = UUID()
        let (first, second) = (window(), window())
        waits.begin(token)
        waits.add([first], to: token)
        waits.add([second], to: token)
        waits.endOpening(token)
        #expect(posted.isEmpty)
        first.close()
        #expect(posted.isEmpty)
        second.close()
        #expect(posted == [token])
        #expect(waits.pendingTokens.isEmpty)
    }

    @Test("a window closed while files are still opening doesn't end the wait early")
    func stillOpening() {
        let waits = waits()
        let token = UUID()
        let first = window()
        waits.begin(token)
        waits.add([first], to: token)
        first.close()
        #expect(posted.isEmpty)
        waits.endOpening(token)
        #expect(posted == [token])
    }

    @Test("a token whose files all failed is notified when opening ends")
    func nothingOpened() {
        let waits = waits()
        let token = UUID()
        waits.begin(token)
        waits.endOpening(token)
        #expect(posted == [token])
    }

    @Test("two tokens on one window both end when it closes; other windows don't matter")
    func sharedWindow() {
        let waits = waits()
        let (one, two) = (UUID(), UUID())
        let (shared, unrelated) = (window(), window())
        for token in [one, two] {
            waits.begin(token)
            waits.add([shared], to: token)
            waits.endOpening(token)
        }
        unrelated.close()
        #expect(posted.isEmpty)
        shared.close()
        #expect(Set(posted) == [one, two])
    }

    @Test("windows for an unknown token are ignored, and quitting notifies every token")
    func quit() {
        let waits = waits()
        waits.add([window()], to: UUID())
        #expect(waits.pendingTokens.isEmpty)
        let token = UUID()
        waits.begin(token)
        waits.add([window()], to: token)
        waits.endOpening(token)
        waits.notifyAll()
        #expect(posted == [token])
        #expect(waits.pendingTokens.isEmpty)
    }

    @Test("DocumentOpener waits on the windows it opens, and on an already-open file's window")
    func opener() async throws {
        let waits = waits()
        let opener = DocumentOpener(
            themeSettings: ThemeSettings(defaults: throwawayDefaults.defaults, isPersistent: true), waits: waits,
            presentError: { _ in })
        let (fileA, fileB) = (try file("a.md"), try file("b.md"))
        defer {
            for document in opened { document.close() }
        }
        func open(_ urls: [URL], token: UUID?) async {
            await withCheckedContinuation { continuation in
                opener.open(urls, parameters: AppOpenParameters(waitToken: token)) { continuation.resume() }
            }
            for url in urls {
                if let document = NSDocumentController.shared.document(for: url),
                    !opened.contains(where: { $0 === document })
                {
                    opened.append(document)
                }
            }
        }

        await open([fileA], token: nil)
        #expect(waits.pendingTokens.isEmpty)
        let token = UUID()
        await open([fileA, fileB], token: token)
        #expect(waits.pendingTokens == [token])

        let documentA = try #require(NSDocumentController.shared.document(for: fileA))
        let documentB = try #require(NSDocumentController.shared.document(for: fileB))
        documentA.close()
        #expect(posted.isEmpty)
        documentB.close()
        #expect(posted == [token])
        opened.removeAll()
    }
}
