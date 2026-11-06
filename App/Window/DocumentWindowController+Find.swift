import AppKit

/// Find in page (#25): Edit > Find commands, sent up the responder chain as the standard
/// `performTextFinderAction(_:)` with an `NSTextFinder.Action` tag. `WKWebView` doesn't
/// implement it (no public find bar), so the commands reach this controller.
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
