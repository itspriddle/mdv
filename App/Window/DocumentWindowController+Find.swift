import AppKit

/// Find in page (#25, #42): Edit > Find commands, sent up the responder chain as the standard
/// `performTextFinderAction(_:)` with an `NSTextFinder.Action` tag. `WKWebView` doesn't
/// implement it (no public find bar), so the commands reach this controller. Jump to Selection
/// is the standard `centerSelectionInVisibleArea(_:)`, which `DocumentWebView` and the find
/// field's editor pass on to here.
extension DocumentWindowController {
    override func performTextFinderAction(_ sender: Any?) {
        guard let tag = (sender as? any NSValidatedUserInterfaceItem)?.tag,
            let action = NSTextFinder.Action(rawValue: tag)
        else {
            return
        }
        let find = coordinator.find
        switch action {
        case .showFindInterface:
            find.show()
        case .nextMatch:
            find.next()
        case .previousMatch:
            find.previous()
        case .setSearchString:
            find.useSelection()
        case .hideFindInterface:
            find.hide()
        default:
            break
        }
    }

    /// Jump to Selection (Cmd-J): scrolls the current match or the selected text into view.
    override func centerSelectionInVisibleArea(_ sender: Any?) {
        coordinator.find.jumpToSelection()
    }

    /// Whether an Edit > Find item is enabled: the commands this window performs. Called from
    /// the window controller's `validateMenuItem(_:)`.
    func validateFindItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(performTextFinderAction(_:)) else {
            return true
        }
        switch NSTextFinder.Action(rawValue: menuItem.tag) {
        case .showFindInterface, .nextMatch, .previousMatch, .setSearchString:
            return true
        case .hideFindInterface:
            return coordinator.find.isVisible
        default:
            return false
        }
    }

    /// Esc in the page closes the find bar when it is open.
    override func cancelOperation(_ sender: Any?) {
        if coordinator.find.isVisible {
            coordinator.find.hide()
        } else {
            super.cancelOperation(sender)
        }
    }

    /// Runs the open search again after new content is shown (live reload, a full reload).
    func refreshFind() async {
        await coordinator.find.refresh()
    }
}
