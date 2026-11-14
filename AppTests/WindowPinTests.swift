import AppKit
import Foundation
import Testing

@testable import PeepApp

/// Pinned windows: the window level, the Window menu item and status bar state, tab groups,
/// the default for new windows (Settings only), and restoration.
@MainActor
@Suite("Window pin", .serialized, .timeLimit(.minutes(1)))
final class WindowPinTests: DocumentWindowTestCase {
    var preference: WindowPinPreference {
        WindowPinPreference(defaults: defaults, isPersistent: true)
    }

    @Test("new windows are unpinned until Settings pins them")
    func unpinnedByDefault() async throws {
        defer { closeAll() }
        let (_, controller) = try await open()
        #expect(!controller.isPinned)
        #expect(controller.window?.level == .normal)

        preference.pinsNewWindows = true
        let (_, pinned) = try await open(name: "pinned.md")
        #expect(pinned.isPinned)
        #expect(pinned.statusBar.isPinned)
        #expect(pinned.window?.level == .floating)
    }

    @Test("toggling floats the window and retitles the item, without changing the default")
    func toggle() async throws {
        defer { closeAll() }
        let (_, controller) = try await open()
        let item = NSMenuItem("Pin Window", action: #selector(DocumentWindowController.togglePinned(_:)))
        #expect(controller.validateMenuItem(item))
        #expect(item.title == "Pin Window")

        controller.togglePinned(nil)
        #expect(controller.isPinned)
        #expect(controller.statusBar.isPinned)
        #expect(controller.window?.level == .floating)
        #expect(controller.validateMenuItem(item))
        #expect(item.title == "Unpin Window")
        #expect(defaults.object(forKey: WindowPinPreference.key) == nil)

        controller.togglePinned(nil)
        #expect(!controller.isPinned)
        #expect(controller.window?.level == .normal)
    }

    @Test("a pin belongs to the tab group, and a tab joining a pinned group is pinned")
    func tabGroup() async throws {
        defer { closeAll() }
        let (_, first) = try await open(name: "first.md")
        let (_, second) = try await open(name: "second.md")
        let (_, third) = try await open(name: "third.md")
        let firstWindow = try #require(first.window)
        let secondWindow = try #require(second.window)
        let thirdWindow = try #require(third.window)
        first.showWindow(nil)
        second.showWindow(nil)
        firstWindow.addTabbedWindow(secondWindow, ordered: .above)
        try await until("the tab group") { (firstWindow.tabbedWindows?.count ?? 0) == 2 }

        second.togglePinned(nil)
        #expect(first.isPinned)
        #expect(second.isPinned)
        #expect(firstWindow.level == .floating)

        third.showWindow(nil)
        firstWindow.addTabbedWindow(thirdWindow, ordered: .above)
        try await until("the third tab") { (firstWindow.tabbedWindows?.count ?? 0) == 3 }
        third.adoptTabGroupPin()
        #expect(third.isPinned)

        first.togglePinned(nil)
        #expect(!first.isPinned)
        #expect(!second.isPinned)
        #expect(!third.isPinned)
    }

    @Test("an unpinned tab adopts its group's pin when it becomes key")
    func adoptsOnBecomingKey() async throws {
        defer { closeAll() }
        let (_, first) = try await open(name: "first.md")
        let (_, second) = try await open(name: "second.md")
        let firstWindow = try #require(first.window)
        let secondWindow = try #require(second.window)
        first.showWindow(nil)
        second.showWindow(nil)
        firstWindow.addTabbedWindow(secondWindow, ordered: .above)
        try await until("the tab group") { (firstWindow.tabbedWindows?.count ?? 0) == 2 }
        first.isPinned = true
        #expect(!second.isPinned)

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: secondWindow)
        #expect(second.isPinned)
        #expect(secondWindow.level == .floating)
    }

    @Test("window restoration keeps each window's pin over the default")
    func restoration() async throws {
        defer { closeAll() }
        let (_, controller) = try await open()
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        controller.encodePinState(with: archiver)
        archiver.finishEncoding()

        preference.pinsNewWindows = true
        let (_, restored) = try await open(name: "restored.md")
        #expect(restored.isPinned)
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        restored.restorePinState(with: unarchiver)
        #expect(!restored.isPinned)
        #expect(restored.window?.level == .normal)

        let window = try #require(controller.window)
        let coder = KeyRecordingCoder()
        window.encodeRestorableState(with: coder)
        #expect(coder.keys.contains(DocumentWindowController.pinnedStateKey))
    }

    @Test("Window > Pin Window is Option-Command-P")
    func menuItem() throws {
        let menuItem = try #require(item("Pin Window", in: "Window"))
        #expect(menuItem.keyEquivalent == "p")
        #expect(menuItem.keyEquivalentModifierMask == [.command, .option])
        #expect(menuItem.action == #selector(DocumentWindowController.togglePinned(_:)))
    }

    @Test("a UI-test preference never writes the reader's defaults")
    func nonPersistentPreference() {
        WindowPinPreference(defaults: defaults, isPersistent: false).pinsNewWindows = true
        #expect(defaults.object(forKey: WindowPinPreference.key) == nil)
    }
}
