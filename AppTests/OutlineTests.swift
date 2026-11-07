import AppKit
import Foundation
import MdvCore
import Testing
import WebKit

@testable import MdvApp

/// The outline sidebar (#24), hosted: a `MarkdownDocument` with a window, its outline, the
/// scroll reports from `ScrollPosition.js`, and jumps through the bridge.
@MainActor
@Suite("Outline", .serialized, .timeLimit(.minutes(1)))
final class OutlineTests {
    static let markdownType = "net.daringfireball.markdown"

    /// Three sections of 60 paragraphs each, with a nested heading in the first.
    static let sections = """
        # One

        ## One A

        \(filler("one"))

        # Two

        \(filler("two"))

        # Three

        Short last section.
        """

    static func filler(_ name: String) -> String {
        (1...60).map { "Paragraph \(name) \($0)." }.joined(separator: "\n\n")
    }

    let folder: URL
    let file: URL
    let throwawayDefaults: ThrowawayDefaults
    var defaults: UserDefaults { throwawayDefaults.defaults }
    var documents: [MarkdownDocument] = []

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "mdv-outline-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = folder.appending(path: "notes.md")
        throwawayDefaults = try ThrowawayDefaults("mdv-outline-tests")
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    var preference: OutlinePreference {
        OutlinePreference(defaults: defaults, isPersistent: true)
    }

    /// Opens `source` in a window with the outline shown, once the page has loaded.
    func open(_ source: String, outlineVisible: Bool = true) async throws -> (
        MarkdownDocument, DocumentWindowController
    ) {
        try Data(source.utf8).write(to: file)
        let document = try MarkdownDocument(contentsOf: file, ofType: Self.markdownType)
        documents.append(document)
        preference.showsOutlineInNewWindows = outlineVisible
        let controller = DocumentWindowController(outlinePreference: preference)
        document.addWindowController(controller)
        controller.window?.layoutIfNeeded()
        try await until("the first load") { controller.coordinator.hasLoadedPage }
        // The first display ends by focusing the web view; wait, so it doesn't take focus from
        // the outline mid-test.
        try await until("the web view focused") { controller.window?.firstResponder === controller.coordinator.webView }
        return (document, controller)
    }

    func close() {
        documents.forEach { $0.close() }
        documents.removeAll()
    }

    func until(_ what: String, timeout: Duration = .seconds(5), _ condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while try await !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("timed out waiting for \(what)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func scrollY(_ controller: DocumentWindowController) async throws -> Double {
        let result = try await controller.coordinator.webView.callAsyncJavaScript(
            "return window.scrollY;", arguments: [:], in: nil, contentWorld: AppScripts.world)
        return try #require(result as? NSNumber).doubleValue
    }

    func selectedID(_ outline: OutlineViewController) -> String? {
        (outline.outlineView.item(atRow: outline.outlineView.selectedRow) as? OutlineItem)?.entry.id
    }

    func row(_ id: String, in outline: OutlineViewController) -> Int {
        let view = outline.outlineView
        return (0..<view.numberOfRows).first { (view.item(atRow: $0) as? OutlineItem)?.entry.id == id } ?? -1
    }

    func rowIDs(_ outline: OutlineViewController) -> [String] {
        let view = outline.outlineView
        return (0..<view.numberOfRows).compactMap { (view.item(atRow: $0) as? OutlineItem)?.entry.id }
    }

    // MARK: Contents

    @Test("lists every heading, nested, including duplicate and raw HTML headings")
    func contents() async throws {
        defer { close() }
        let (_, controller) = try await open("# Notes\n\n## Example\n\n## Example\n\n<h2>Raw</h2>\n\n# Notes\n")
        let outline = controller.outlineController
        #expect(rowIDs(outline) == ["notes", "example", "example-1", "raw", "notes-1"])
        #expect(outline.outlineView.level(forRow: 1) == 1)
        let cell = outline.outlineView.view(atColumn: 0, row: 2, makeIfNecessary: true) as? NSTableCellView
        #expect(cell?.textField?.stringValue == "Example")
        #expect(outline.outlineView.enclosingScrollView?.isHidden == false)
    }

    @Test("a document without headings shows the empty state")
    func emptyState() async throws {
        defer { close() }
        let (_, controller) = try await open("Just text.\n")
        let outline = controller.outlineController
        #expect(outline.outlineView.numberOfRows == 0)
        #expect(outline.outlineView.enclosingScrollView?.isHidden == true)
        let empty = outline.view.subviews.first { $0.accessibilityIdentifier() == "document-outline-empty" }
        #expect(empty?.isHidden == false)
    }

    // MARK: Current section

    @Test("scrolling the document highlights the current section")
    func tracksScrolling() async throws {
        defer { close() }
        let (_, controller) = try await open(Self.sections)
        let outline = controller.outlineController
        try await until("section one at the top") { selectedID(outline) == "one" }
        try await controller.coordinator.scroll(toFragment: "two")
        try await until("section two") { selectedID(outline) == "two" }
        #expect(outline.tracker.currentSection == "two")
        // Back up into the nested section.
        try await controller.coordinator.scroll(toFragment: "one-a")
        try await until("section one-a") { selectedID(outline) == "one-a" }
    }

    @Test("a collapsed entry is highlighted for a section inside it")
    func collapsedSection() async throws {
        defer { close() }
        let (_, controller) = try await open(Self.sections)
        let outline = controller.outlineController
        let one = try #require(outline.outlineView.item(atRow: row("one", in: outline)))
        outline.outlineView.collapseItem(one)
        #expect(outline.collapsedIDs == ["one"])
        try await controller.coordinator.scroll(toFragment: "one-a")
        try await until("the collapsed parent row") { outline.tracker.currentSection == "one-a" }
        #expect(selectedID(outline) == "one")
    }

    // MARK: Jumping

    @Test("Return on a heading jumps to it and keeps it selected")
    func returnJumps() async throws {
        defer { close() }
        let (_, controller) = try await open(Self.sections)
        let outline = controller.outlineController
        let view = outline.outlineView
        controller.window?.makeFirstResponder(view)
        view.selectRowIndexes(IndexSet(integer: row("two", in: outline)), byExtendingSelection: false)
        let returnKey = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: controller.window?.windowNumber ?? 0, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        view.keyDown(with: returnKey)
        try await until("the document scrolled") { try await scrollY(controller) > 0 }
        try await until("the jump landed") { outline.tracker.currentSection == "two" }
        #expect(selectedID(outline) == "two")
    }

    @Test("a jump to a short section near the end keeps it selected until the reader scrolls")
    func jumpToLastSection() async throws {
        defer { close() }
        let (_, controller) = try await open(Self.sections + "\n\n# Four\n\nShort too.")
        let outline = controller.outlineController
        controller.window?.makeFirstResponder(outline.outlineView)
        outline.outlineView.selectRowIndexes(IndexSet(integer: row("three", in: outline)), byExtendingSelection: false)
        outline.outlineView.onActivate?()
        // The page is at the bottom: "Three" can't reach the top of the view, and the section
        // at the bottom of the page is "Four".
        try await until("the jump landed") { outline.tracker.currentSection == "four" }
        try await Task.sleep(for: .milliseconds(300))
        #expect(selectedID(outline) == "three")
        try await controller.coordinator.scroll(toFragment: "one")
        try await until("section one") { selectedID(outline) == "one" }
    }

    @Test("scrolling to the end makes each short last section current in turn (#43)")
    func shortLastSections() async throws {
        defer { close() }
        let (_, controller) = try await open(Self.sections + "\n\n# Four\n\nShort too.")
        let outline = controller.outlineController
        try await until("section one at the top") { selectedID(outline) == "one" }
        try await scroll(controller, toBottomMinus: 0)
        try await until("the last section at the bottom") { selectedID(outline) == "four" }
        // Scrolling back up from the bottom, 20 px at a time: the current section goes through
        // every trailing section, in order.
        var sections: [String] = []
        for step in 0...40 {
            try await scroll(controller, toBottomMinus: Double(step * 20))
            let line = try await controller.coordinator.sectionSourceLine()
            if let section = outline.tracker.outline.section(atSourceLine: line), sections.last != section {
                sections.append(section)
            }
        }
        #expect(sections == ["four", "three", "two"])
    }

    /// Scrolls to `distance` CSS pixels above the bottom of the page.
    func scroll(_ controller: DocumentWindowController, toBottomMinus distance: Double) async throws {
        _ = try await controller.coordinator.webView.callAsyncJavaScript(
            "window.scrollTo(0, document.documentElement.scrollHeight - window.innerHeight - distance); return true;",
            arguments: ["distance": distance], in: nil, contentWorld: AppScripts.world)
    }

    @Test("a heading without a matching element falls back to its source line")
    func jumpBySourceLine() async throws {
        defer { close() }
        let (_, controller) = try await open(Self.sections)
        let two = try #require(controller.outlineController.tracker.outline.headings.first { $0.slug == "two" })
        var missing = two
        missing.slug = "no-such-id"
        controller.jump(to: missing)
        try await until("scrolled to the line") {
            try await controller.coordinator.sectionSourceLine() >= Double(two.sourceLine ?? 0)
        }
    }

    @Test("browsing the outline with the keyboard keeps the selection while the document scrolls")
    func browsingKeepsSelection() async throws {
        defer { close() }
        let (_, controller) = try await open(Self.sections)
        let outline = controller.outlineController
        let view = outline.outlineView
        controller.window?.makeFirstResponder(view)
        view.selectRowIndexes(IndexSet(integer: row("three", in: outline)), byExtendingSelection: false)
        try await controller.coordinator.scroll(toFragment: "two")
        try await until("section two") { outline.tracker.currentSection == "two" }
        #expect(selectedID(outline) == "three")
        // Leaving the outline hands the selection back to the reading position.
        controller.window?.makeFirstResponder(controller.coordinator.webView)
        #expect(selectedID(outline) == "two")
    }

    // MARK: Live reload

    @Test("a re-render keeps the outline's scroll position, collapsed entries, and selection")
    func reloadKeepsState() async throws {
        defer { close() }
        let headings = (1...80).map { "# Heading \($0)\n\n## Sub \($0)\n\ntext" }.joined(separator: "\n\n")
        let (document, controller) = try await open(headings)
        let outline = controller.outlineController
        let view = outline.outlineView
        let clip = try #require(view.enclosingScrollView?.contentView)
        let first = try #require(view.item(atRow: row("heading-1", in: outline)))
        view.collapseItem(first)
        try await controller.coordinator.scroll(toFragment: "heading-40")
        try await until("section 40") { selectedID(outline) == "heading-40" }
        clip.scroll(to: NSPoint(x: 0, y: 300))
        let rowsBefore = view.numberOfRows

        document.setContent(DocumentContent(source: headings + "\n\n# Appended\n", fallbackTitle: "notes.md"))
        try await until("the new heading") { row("appended", in: outline) >= 0 }

        #expect(view.numberOfRows == rowsBefore + 1)
        #expect(clip.bounds.origin.y == 300)
        #expect(!view.isItemExpanded(view.item(atRow: row("heading-1", in: outline))))
        #expect(view.isItemExpanded(view.item(atRow: row("heading-2", in: outline))))
        #expect(selectedID(outline) == "heading-40")
    }
}

// MARK: - Visibility

extension OutlineTests {
    @Test("toggling shows and hides the outline and sets the default for new windows")
    func toggle() async throws {
        defer { close() }
        let (_, controller) = try await open("# One\n", outlineVisible: false)
        #expect(!controller.isOutlineVisible)
        let item = NSMenuItem("Show Outline", action: #selector(DocumentWindowController.toggleOutline(_:)))
        #expect(controller.validateMenuItem(item))
        #expect(item.title == "Show Outline")

        controller.toggleOutline(nil)
        #expect(controller.isOutlineVisible)
        #expect(defaults.bool(forKey: OutlinePreference.key))
        #expect(controller.validateMenuItem(item))
        #expect(item.title == "Hide Outline")

        let next = DocumentWindowController(outlinePreference: preference)
        #expect(next.isOutlineVisible)

        // Restoration sets a window's visibility without changing the default.
        next.isOutlineVisible = false
        #expect(!next.isOutlineVisible)
        #expect(defaults.bool(forKey: OutlinePreference.key))
    }

    @Test("window restoration keeps each window's outline visibility")
    func restoration() async throws {
        defer { close() }
        let (_, controller) = try await open("# One\n", outlineVisible: true)
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        controller.encodeOutlineState(with: archiver)
        archiver.finishEncoding()

        let (_, restored) = try await open("# One\n", outlineVisible: false)
        #expect(!restored.isOutlineVisible)
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        restored.restoreOutlineState(with: unarchiver)
        #expect(restored.isOutlineVisible)
        #expect(!defaults.bool(forKey: OutlinePreference.key), "restoring doesn't change the default")

        let window = try #require(controller.window)
        let coder = KeyRecordingCoder()
        window.encodeRestorableState(with: coder)
        #expect(coder.keys.contains(DocumentWindowController.outlineVisibleStateKey))
    }

    @Test("the window has an outline toolbar button")
    func toolbarButton() async throws {
        defer { close() }
        let (_, controller) = try await open("# One\n")
        let toolbar = try #require(controller.window?.toolbar)
        let item = try #require(
            toolbar.items.first { $0.itemIdentifier == DocumentWindowController.toggleOutlineToolbarItem })
        #expect(item.action == #selector(DocumentWindowController.toggleOutline(_:)))
    }

    @Test("View > Show Outline is Command-Control-S")
    func menuItem() throws {
        let view = try #require(MainMenu.build().item(withTitle: "View")?.submenu)
        let item = try #require(view.item(withTitle: "Show Outline"))
        #expect(item.keyEquivalent == "s")
        #expect(item.keyEquivalentModifierMask == [.command, .control])
    }

    @Test("a UI-test preference never writes the reader's defaults")
    func nonPersistentPreference() {
        let preference = OutlinePreference(defaults: defaults, isPersistent: false)
        preference.showsOutlineInNewWindows = true
        #expect(defaults.object(forKey: OutlinePreference.key) == nil)
    }

    // MARK: Scroll reports

    @Test("the scroll position handler is invisible to the page world")
    func handlerNotInPageWorld() async throws {
        defer { close() }
        let (_, controller) = try await open("text")
        let script = "return typeof globalThis.webkit?.messageHandlers?.scrollPosition;"
        let webView = controller.coordinator.webView
        let pageWorld = try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        #expect(pageWorld as? String == "undefined")
        let appWorld = try await webView.callAsyncJavaScript(
            script, arguments: [:], in: nil, contentWorld: AppScripts.world)
        #expect(appWorld as? String == "object")
    }
}
