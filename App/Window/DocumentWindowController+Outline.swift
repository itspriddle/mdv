import AppKit
import MdvCore

/// The outline sidebar (#24): a sidebar split item beside the document, toggled from the View
/// menu and the toolbar, jumping to headings through the scroll bridge and following the
/// reading position that `ScrollPosition.js` reports.
extension DocumentWindowController {
    static let toggleOutlineToolbarItem = NSToolbarItem.Identifier("toggleOutline")

    /// Whether this window shows the outline. Window restoration (#22) can save and set this;
    /// setting it doesn't change the default for new windows (`OutlinePreference`).
    var isOutlineVisible: Bool {
        get { outlineSidebarItem.map { !$0.isCollapsed } ?? wantsOutline }
        set { setOutlineVisible(newValue, animated: false) }
    }

    /// View > Show/Hide Outline and the toolbar button. The choice becomes the default for new
    /// windows.
    @objc func toggleOutline(_ sender: Any?) {
        let visible = !isOutlineVisible
        setOutlineVisible(visible, animated: true)
        outlinePreference.showsOutlineInNewWindows = visible
    }

    func setOutlineVisible(_ visible: Bool, animated: Bool) {
        wantsOutline = visible
        if let outlineSidebarItem, outlineSidebarItem.isCollapsed == visible {
            if animated {
                outlineSidebarItem.animator().isCollapsed = !visible
            } else {
                outlineSidebarItem.isCollapsed = !visible
            }
        }
        window?.invalidateRestorableState()
    }

    /// Called from `init`: the toolbar, and the outline's links to the web view.
    func installOutline() {
        coordinator.sectionLineDidChange = { [weak self] line in
            self?.outlineController.scrolled(to: line)
        }
        outlineController.onJump = { [weak self] heading in
            self?.jump(to: heading)
        }
        let toolbar = NSToolbar(identifier: "DocumentWindow")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    /// The window's content: the outline sidebar and the document.
    func makeSplitViewController(content: NSViewController) -> NSSplitViewController {
        let splitViewController = NSSplitViewController()
        let sidebar = NSSplitViewItem(sidebarWithViewController: outlineController)
        sidebar.minimumThickness = 160
        sidebar.maximumThickness = 420
        sidebar.canCollapse = true
        sidebar.canCollapseFromWindowResize = false
        sidebar.isCollapsed = !wantsOutline
        let document = NSSplitViewItem(viewController: content)
        document.minimumThickness = 480
        splitViewController.splitViewItems = [sidebar, document]
        splitViewController.view.frame.size = window?.contentLayoutRect.size ?? .zero
        outlineSidebarItem = sidebar
        return splitViewController
    }

    /// Scrolls to `heading` by its anchor (`slug`), or by its source line if no element has
    /// that id, then tells the outline where the jump landed.
    func jump(to heading: Heading) {
        Task { [coordinator, outlineController] in
            let found = (try? await coordinator.scroll(toFragment: heading.slug)) ?? false
            if !found, let line = heading.sourceLine {
                try? await coordinator.scroll(toSourceLine: Double(line))
            }
            if let line = try? await coordinator.sectionSourceLine() {
                outlineController.landed(at: line)
            }
        }
    }

    /// Reads the reading position after a (re)display, since source lines may have moved.
    func updateOutlinePosition() async {
        if let line = try? await coordinator.sectionSourceLine() {
            outlineController.scrolled(to: line)
        }
    }
}

extension DocumentWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleOutline(_:)):
            menuItem.title = isOutlineVisible ? "Hide Outline" : "Show Outline"
            return true
        default:
            return true
        }
    }
}

extension DocumentWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.toggleOutlineToolbarItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.toggleOutlineToolbarItem]
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.toggleOutlineToolbarItem else {
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Outline"
        item.paletteLabel = "Outline"
        item.toolTip = "Show or hide the outline"
        item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Outline")
        item.isBordered = true
        item.target = self
        item.action = #selector(toggleOutline(_:))
        return item
    }
}
