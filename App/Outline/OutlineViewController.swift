import AppKit
import MdvCore

/// The outline sidebar: the document's headings as an `NSOutlineView`, nested by level.
///
/// - A click or Return on a heading asks the window to jump to it (`onJump`).
/// - The selection shows the current section (`OutlineTracker`): it follows scroll reports
///   (`scrolled(to:)`) except while the reader browses the outline with the keyboard.
/// - A re-render (`show(_:)`) keeps the sidebar's scroll position and which headings are
///   collapsed; an unchanged outline is not reloaded at all.
/// - A document without headings shows "No Headings".
/// - Expand All and Collapse All (`expandAll()`, `collapseAll()`; the View menu and the
///   sidebar's context menu, #43) open or close every entry.
@MainActor
final class OutlineViewController: NSViewController {
    /// Asks the window to scroll the document to a heading.
    var onJump: ((Heading) -> Void)?

    private(set) var tracker = OutlineTracker()
    /// Collapsed entries, by slug. Entries are expanded unless listed here, so new headings
    /// arrive expanded and collapsed ones stay collapsed across re-renders.
    private(set) var collapsedIDs: Set<String> = []

    let outlineView = OutlineTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No Headings")
    private var rootItems: [OutlineItem] = []
    private var itemsByID: [String: OutlineItem] = [:]
    /// Set while the outline changes rows or selection itself, so delegate callbacks for those
    /// changes aren't mistaken for the reader's.
    private var isUpdating = false
    /// Set while the reader collapses an entry: the outline moves a hidden selection to the
    /// collapsed row, which isn't the reader choosing it.
    private var isCollapsing = false

    override func loadView() {
        let column = NSTableColumn(identifier: OutlineItem.cellIdentifier)
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outlineView.allowsEmptySelection = true
        outlineView.allowsMultipleSelection = false
        outlineView.autoresizesOutlineColumn = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked(_:))
        outlineView.onActivate = { [weak self] in self?.jumpToSelectedRow() }
        outlineView.onResignFocus = { [weak self] in self?.stoppedBrowsing() }
        outlineView.menu = makeContextMenu()
        outlineView.setAccessibilityLabel("Outline")
        outlineView.setAccessibilityIdentifier("document-outline")

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.setAccessibilityIdentifier("document-outline-empty")

        let view = NSView()
        for subview in [scrollView, emptyLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 8),
        ])
        self.view = view
        updateEmptyState()
    }

    // MARK: Updates from the window

    /// Shows `outline`, keeping the scroll position, collapsed entries, and selection where
    /// their headings remain.
    func show(_ outline: DocumentOutline) {
        loadViewIfNeeded()
        guard outline != tracker.outline else {
            return
        }
        tracker.update(outline)
        let origin = scrollView.contentView.bounds.origin
        isUpdating = true
        rootItems = outline.roots.map(OutlineItem.init)
        itemsByID = [:]
        index(rootItems)
        collapsedIDs.formIntersection(itemsByID.keys)
        outlineView.reloadData()
        expand(rootItems)
        isUpdating = false
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateEmptyState()
        applySelection(scrollingToSelection: false)
    }

    /// The document scrolled: `line` is its `sectionSourceLine()`.
    func scrolled(to line: Double) {
        tracker.scrolled(to: line)
        applySelection(scrollingToSelection: true)
    }

    /// A jump finished with the document at `line`.
    func landed(at line: Double) {
        tracker.landed(at: line)
    }

    // MARK: Expand and collapse all

    /// Whether some entry is collapsed (Expand All has something to do).
    var canExpandAll: Bool {
        !collapsedIDs.isEmpty
    }

    /// Whether some entry with children is expanded (Collapse All has something to do).
    var canCollapseAll: Bool {
        itemsByID.values.contains { !$0.children.isEmpty && !collapsedIDs.contains($0.entry.id) }
    }

    /// Expands every entry.
    func expandAll() {
        collapsedIDs.removeAll()
        isUpdating = true
        outlineView.expandItem(nil, expandChildren: true)
        isUpdating = false
        applySelection(scrollingToSelection: true)
    }

    /// Collapses every entry, nested ones too, so expanding a top-level entry shows only its
    /// direct children. The current section's top-level entry stays selected.
    func collapseAll() {
        collapsedIDs = Set(itemsByID.values.filter { !$0.children.isEmpty }.map(\.entry.id))
        isUpdating = true
        outlineView.collapseItem(nil, collapseChildren: true)
        isUpdating = false
        applySelection(scrollingToSelection: true)
    }

    @objc func expandAllEntries(_ sender: Any?) {
        expandAll()
    }

    @objc func collapseAllEntries(_ sender: Any?) {
        collapseAll()
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Outline")
        for (title, action) in [
            ("Expand All", #selector(expandAllEntries(_:))), ("Collapse All", #selector(collapseAllEntries(_:))),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    // MARK: Reader actions

    @objc private func rowClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, !outlineView.isClickOnDisclosureTriangle(row: row) else {
            return
        }
        jump(toRow: row)
    }

    private func jumpToSelectedRow() {
        jump(toRow: outlineView.selectedRow)
    }

    private func jump(toRow row: Int) {
        guard let item = outlineView.item(atRow: row) as? OutlineItem else {
            return
        }
        tracker.jumped(to: item.entry.id)
        applySelection(scrollingToSelection: false)
        onJump?(item.entry.heading)
    }

    private func stoppedBrowsing() {
        tracker.stoppedBrowsing()
        applySelection(scrollingToSelection: true)
    }

    // MARK: Helpers

    private func index(_ items: [OutlineItem]) {
        for item in items {
            itemsByID[item.entry.id] = item
            index(item.children)
        }
    }

    private func expand(_ items: [OutlineItem]) {
        for item in items where !item.children.isEmpty && !collapsedIDs.contains(item.entry.id) {
            outlineView.expandItem(item)
            expand(item.children)
        }
    }

    /// Selects the tracker's selection, or the closest visible row when it is inside a collapsed
    /// entry.
    private func applySelection(scrollingToSelection: Bool) {
        let row = visibleRow(for: tracker.selection)
        let current = outlineView.selectedRow
        guard row != current else {
            return
        }
        isUpdating = true
        if row >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            if scrollingToSelection {
                outlineView.scrollRowToVisible(row)
            }
        } else {
            outlineView.deselectAll(nil)
        }
        isUpdating = false
    }

    private func visibleRow(for id: String?) -> Int {
        guard let id else {
            return -1
        }
        // The outermost collapsed ancestor is the visible row that contains the entry.
        let collapsedAncestor = tracker.outline.ancestors(of: id).first { collapsedIDs.contains($0) }
        guard let item = itemsByID[collapsedAncestor ?? id] else {
            return -1
        }
        return outlineView.row(forItem: item)
    }

    private func updateEmptyState() {
        let isEmpty = rootItems.isEmpty
        emptyLabel.isHidden = !isEmpty
        scrollView.isHidden = isEmpty
    }
}

extension OutlineViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(expandAllEntries(_:)): canExpandAll
        case #selector(collapseAllEntries(_:)): canCollapseAll
        default: true
        }
    }
}

// MARK: - Data source and delegate

extension OutlineViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        children(of: item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !children(of: item).isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? OutlineItem else {
            return nil
        }
        let cell =
            outlineView.makeView(withIdentifier: OutlineItem.cellIdentifier, owner: nil) as? NSTableCellView
            ?? OutlineItem.makeCell()
        cell.textField?.stringValue = item.entry.heading.text
        cell.toolTip = item.entry.heading.text
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdating, !isCollapsing else {
            return
        }
        let item = outlineView.item(atRow: outlineView.selectedRow) as? OutlineItem
        tracker.browsed(to: item?.entry.id)
    }

    func outlineViewItemWillCollapse(_ notification: Notification) {
        isCollapsing = !isUpdating
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isUpdating, let item = notification.userInfo?["NSObject"] as? OutlineItem else {
            return
        }
        isCollapsing = false
        collapsedIDs.insert(item.entry.id)
        applySelection(scrollingToSelection: false)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isUpdating, let item = notification.userInfo?["NSObject"] as? OutlineItem else {
            return
        }
        collapsedIDs.remove(item.entry.id)
        // Children collapsed before keep their state; expanding the parent doesn't reopen them.
        isUpdating = true
        expand(item.children)
        isUpdating = false
    }

    private func children(of item: Any?) -> [OutlineItem] {
        guard let item = item as? OutlineItem else {
            return rootItems
        }
        return item.children
    }
}

// MARK: - Items and the view

/// One row: an outline entry, as the reference type `NSOutlineView` identifies items by.
@MainActor
final class OutlineItem: NSObject {
    static let cellIdentifier = NSUserInterfaceItemIdentifier("OutlineCell")

    let entry: DocumentOutline.Entry
    let children: [OutlineItem]

    init(_ entry: DocumentOutline.Entry) {
        self.entry = entry
        self.children = entry.children.map(OutlineItem.init)
    }

    static func makeCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = cellIdentifier
        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.truncatesLastVisibleLine = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

/// The outline's `NSOutlineView`: Return or Enter activates the selected row, and losing
/// keyboard focus is reported, so browsing with the keyboard ends.
@MainActor
final class OutlineTableView: NSOutlineView {
    var onActivate: (() -> Void)?
    var onResignFocus: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "\r", "\u{3}":
            onActivate?()
        default:
            super.keyDown(with: event)
        }
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            onResignFocus?()
        }
        return resigned
    }

    /// Whether the event being handled is a click on `row`'s disclosure triangle.
    func isClickOnDisclosureTriangle(row: Int) -> Bool {
        guard let event = window?.currentEvent, event.type == .leftMouseUp || event.type == .leftMouseDown else {
            return false
        }
        let point = convert(event.locationInWindow, from: nil)
        return frameOfOutlineCell(atRow: row).contains(point)
    }
}
