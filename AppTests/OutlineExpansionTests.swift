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
