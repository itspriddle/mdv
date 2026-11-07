import AppKit
import Testing

@testable import MdvApp

/// The outline's Expand All and Collapse All (#43): the View menu items and the sidebar's
/// context menu, hosted like the rest of `OutlineTests`.
extension OutlineTests {
    static let nested = """
        # One

        ## One A

        ### One A i

        ## One B

        # Two

        ## Two A
        """

    @Test("Collapse All and Expand All close and open every entry, nested ones too")
    func collapseAndExpandAll() async throws {
        defer { close() }
        let (_, controller) = try await open(Self.nested)
        let outline = controller.outlineController
        let all = ["one", "one-a", "one-a-i", "one-b", "two", "two-a"]
        #expect(rowIDs(outline) == all)
        #expect(!outline.canExpandAll)
        #expect(outline.canCollapseAll)

        controller.collapseAllOutlineEntries(nil)
        #expect(rowIDs(outline) == ["one", "two"])
        #expect(outline.collapsedIDs == ["one", "one-a", "two"])
        #expect(outline.canExpandAll)
        #expect(!outline.canCollapseAll)
        // Nested entries stay collapsed: expanding "One" shows only its children.
        outline.outlineView.expandItem(outline.outlineView.item(atRow: 0))
        #expect(rowIDs(outline) == ["one", "one-a", "one-b", "two"])

        controller.expandAllOutlineEntries(nil)
        #expect(rowIDs(outline) == all)
        #expect(outline.collapsedIDs.isEmpty)
    }

    @Test("collapsing all keeps the current section's visible entry selected")
    func collapseAllKeepsSelection() async throws {
        defer { close() }
        let (_, controller) = try await open(Self.nested)
        let outline = controller.outlineController
        try await until("a current section") { selectedID(outline) != nil }
        controller.collapseAllOutlineEntries(nil)
        #expect(selectedID(outline) == "one")
        controller.expandAllOutlineEntries(nil)
        #expect(selectedID(outline) == outline.tracker.selection)
    }

    @Test("the menu items are enabled only when the visible outline has something to change")
    func expansionMenuValidation() async throws {
        defer { close() }
        let (_, controller) = try await open(Self.nested)
        let view = try #require(MainMenu.build().item(withTitle: "View")?.submenu)
        let expand = try #require(view.item(withTitle: "Expand All Headings"))
        let collapse = try #require(view.item(withTitle: "Collapse All Headings"))
        #expect(!controller.validateMenuItem(expand))
        #expect(controller.validateMenuItem(collapse))
        controller.collapseAllOutlineEntries(nil)
        #expect(controller.validateMenuItem(expand))
        #expect(!controller.validateMenuItem(collapse))
        controller.setOutlineVisible(false, animated: false)
        #expect(!controller.validateMenuItem(expand))

        // The sidebar's context menu has the same two commands.
        let menu = try #require(controller.outlineController.outlineView.menu)
        #expect(menu.items.map(\.title) == ["Expand All", "Collapse All"])
        let contextExpand = try #require(menu.items.first)
        #expect(controller.outlineController.validateMenuItem(contextExpand))
    }
}

/// The outline sidebar's width, saved per window with window restoration (#43).
extension OutlineTests {
    func sidebarWidth(_ controller: DocumentWindowController) -> CGFloat {
        controller.window?.layoutIfNeeded()
        // The pane, not the sidebar view: macOS 26 insets the view inside its pane.
        let splitView = (controller.outlineSidebarItem?.viewController.parent as? NSSplitViewController)?.splitView
        return splitView?.arrangedSubviews.first?.frame.width ?? 0
    }

    func archivedOutlineState(_ controller: DocumentWindowController) throws -> NSKeyedUnarchiver {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        controller.encodeOutlineState(with: archiver)
        archiver.finishEncoding()
        return try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
    }

    @Test("a resized sidebar's width is saved and restored with the window")
    func widthRestoration() async throws {
        defer { close() }
        let (_, controller) = try await open("# One\n")
        let initial = sidebarWidth(controller)
        controller.applyOutlineWidth(300)
        #expect(sidebarWidth(controller) == 300)
        #expect(initial != 300)
        #expect(controller.outlineWidth == 300)

        let (_, restored) = try await open("# One\n")
        restored.restoreOutlineState(with: try archivedOutlineState(controller))
        #expect(sidebarWidth(restored) == 300)

        let window = try #require(controller.window)
        let coder = KeyRecordingCoder()
        window.encodeRestorableState(with: coder)
        #expect(coder.keys.contains(DocumentWindowController.outlineWidthStateKey))
    }

    @Test("a hidden sidebar's restored width applies when it is shown")
    func widthRestorationWhileHidden() async throws {
        defer { close() }
        let (_, controller) = try await open("# One\n")
        controller.applyOutlineWidth(250)
        controller.setOutlineVisible(false, animated: false)
        let state = try archivedOutlineState(controller)

        let (_, restored) = try await open("# One\n", outlineVisible: false)
        restored.restoreOutlineState(with: state)
        #expect(!restored.isOutlineVisible)
        restored.setOutlineVisible(true, animated: false)
        #expect(sidebarWidth(restored) == 250)
    }

    @Test("restored widths are validated and clamped to the sidebar's limits")
    func widthValidation() async throws {
        defer { close() }
        #expect(DocumentWindowController.validOutlineWidth(.nan) == nil)
        #expect(DocumentWindowController.validOutlineWidth(-1) == nil)
        #expect(DocumentWindowController.validOutlineWidth(.infinity) == nil)
        let (_, controller) = try await open("# One\n")
        controller.applyOutlineWidth(5000)
        #expect(sidebarWidth(controller) == 420)
        controller.applyOutlineWidth(10)
        // The view is held to 160; the pane adds the view's inset (0, or 8 pt on macOS 26).
        let view = try #require(controller.outlineSidebarItem?.viewController.view)
        #expect(view.frame.width == 160)
        #expect(sidebarWidth(controller) == controller.outlineWidth)
    }
}
