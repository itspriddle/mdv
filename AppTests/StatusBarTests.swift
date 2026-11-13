import AppKit
import Foundation
import Testing

@testable import PeepApp

/// The status bar along the bottom of a document window: its visibility (the View menu, the
/// default for new windows, restoration) and the word count it shows.
@MainActor
@Suite("Status bar", .serialized, .timeLimit(.minutes(1)))
final class StatusBarTests: DocumentWindowTestCase {
    var preference: StatusBarPreference {
        StatusBarPreference(defaults: defaults, isPersistent: true)
    }

    @Test("new windows show the status bar until the reader hides it")
    func shownByDefault() async throws {
        defer { closeAll() }
        #expect(defaults.object(forKey: StatusBarPreference.key) == nil)
        let (_, controller) = try await open()
        #expect(controller.isStatusBarVisible)
    }

    @Test("toggling shows and hides the status bar and sets the default for new windows")
    func toggle() async throws {
        defer { closeAll() }
        let (_, controller) = try await open()
        let item = NSMenuItem("Show Status Bar", action: #selector(DocumentWindowController.toggleStatusBar(_:)))
        #expect(controller.validateMenuItem(item))
        #expect(item.title == "Hide Status Bar")

        controller.toggleStatusBar(nil)
        #expect(!controller.isStatusBarVisible)
        #expect(!controller.statusBar.isVisible)
        #expect(defaults.object(forKey: StatusBarPreference.key) as? Bool == false)
        #expect(controller.validateMenuItem(item))
        #expect(item.title == "Show Status Bar")

        let next = DocumentWindowController(statusBarPreference: preference)
        #expect(!next.isStatusBarVisible)

        // Restoration sets a window's visibility without changing the default.
        next.isStatusBarVisible = true
        #expect(defaults.object(forKey: StatusBarPreference.key) as? Bool == false)
    }

    @Test("window restoration keeps each window's status bar visibility")
    func restoration() async throws {
        defer { closeAll() }
        let (_, controller) = try await open()
        controller.isStatusBarVisible = false
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        controller.encodeStatusBarState(with: archiver)
        archiver.finishEncoding()

        let (_, restored) = try await open(name: "restored.md")
        #expect(restored.isStatusBarVisible)
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        restored.restoreStatusBarState(with: unarchiver)
        #expect(!restored.isStatusBarVisible)
        #expect(defaults.object(forKey: StatusBarPreference.key) == nil, "restoring doesn't change the default")

        let window = try #require(controller.window)
        let coder = KeyRecordingCoder()
        window.encodeRestorableState(with: coder)
        #expect(coder.keys.contains(DocumentWindowController.statusBarVisibleStateKey))
    }

    @Test("View > Show Status Bar is Command-/")
    func menuItem() throws {
        let item = try #require(item("Show Status Bar", in: "View"))
        #expect(item.keyEquivalent == "/")
        #expect(item.keyEquivalentModifierMask == [.command])
        #expect(item.action == #selector(DocumentWindowController.toggleStatusBar(_:)))
    }

    @Test("a UI-test preference never writes the reader's defaults")
    func nonPersistentPreference() {
        StatusBarPreference(defaults: defaults, isPersistent: false).showsStatusBarInNewWindows = false
        #expect(defaults.object(forKey: StatusBarPreference.key) == nil)
    }

    @Test("the page carries the document's word count and follows a reload")
    func wordCount() async throws {
        defer { closeAll() }
        let (document, _) = try await open("---\ntitle: Not counted\n---\n# Hello\n\nOne **two** three.")
        #expect(document.content?.page.wordCount == 4)
        let file = try #require(document.fileURL)
        try Data("Just two".utf8).write(to: file, options: .atomic)
        try document.revert(toContentsOf: file, ofType: Self.markdownType)
        try await until("the reloaded word count") { document.content?.page.wordCount == 2 }
    }

    @Test("the word count reads as words, grouped for the locale")
    func wordCountText() {
        #expect(WordCountItem.text(for: 0) == "0 words")
        #expect(WordCountItem.text(for: 1) == "1 word")
        #expect(WordCountItem.text(for: 1_340) == "\(1_340.formatted()) words")
    }
}
