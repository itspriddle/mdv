import AppKit

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
