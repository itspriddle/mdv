import AppKit
import SwiftUI

/// The find bar above the page (Safari/Preview style): search field, match count, previous and
/// next, Match Case, and Done. Hidden while find is closed.
struct FindBar: View {
    let find: FindInPage

    var body: some View {
        if find.isVisible {
            HStack(spacing: 8) {
                FindField(find: find)
                    .frame(minWidth: 160, maxWidth: 320)
                if let status = find.status {
                    Text(status)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(find.isNotFound ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .accessibilityIdentifier("find-status")
                        .accessibilityLabel(status)
                }
                ControlGroup {
                    Button("Previous", systemImage: "chevron.left", action: find.previous)
                        .accessibilityIdentifier("find-previous")
                    Button("Next", systemImage: "chevron.right", action: find.next)
                        .accessibilityIdentifier("find-next")
                }
                .labelStyle(.iconOnly)
                .fixedSize()
                .disabled(find.matchCount == 0)
                Toggle("Match Case", isOn: Binding(get: { find.isCaseSensitive }, set: find.setCaseSensitive))
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("find-case-sensitive")
                Spacer(minLength: 0)
                Button("Done", action: find.hide)
                    .accessibilityIdentifier("find-done")
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("find-bar")
        }
    }
}

/// The find bar's search field. AppKit's `NSSearchField`, for its field editor: Return and
/// Shift-Return step through matches, Esc closes the bar, and Edit > Find commands keep working
/// while it has focus (`FindFieldEditor`).
struct FindField: NSViewRepresentable {
    let find: FindInPage

    func makeNSView(context: Context) -> FindSearchField {
        let field = FindSearchField()
        field.placeholderString = "Find"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("find-field")
        return field
    }

    func updateNSView(_ field: FindSearchField, context: Context) {
        context.coordinator.find = find
        if field.stringValue != find.query {
            field.stringValue = find.query
        }
        if context.coordinator.focusRequest != find.focusRequest {
            context.coordinator.focusRequest = find.focusRequest
            // After this update, once the field is in its window.
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(find: find)
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var find: FindInPage
        var focusRequest = 0

        init(find: FindInPage) {
            self.find = find
        }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField {
                find.setQuery(field.stringValue)
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    find.previous()
                } else {
                    find.next()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                find.hide()
                return true
            default:
                return false
            }
        }
    }
}

/// A search field whose cell edits with `FindFieldEditor`.
final class FindSearchField: NSSearchField {
    override class var cellClass: AnyClass? {
        get { FindSearchFieldCell.self }
        set {}
    }
}

final class FindSearchFieldCell: NSSearchFieldCell {
    private let editor = FindFieldEditor()

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        editor
    }
}

/// A field editor that leaves Edit > Find commands to the window controller. The standard field
/// editor answers `performTextFinderAction(_:)` itself and disables every Find item (it has no
/// find bar of its own), so Cmd-G wouldn't work while typing in the find field.
final class FindFieldEditor: NSTextView {
    convenience init() {
        self.init(frame: .zero)
        isFieldEditor = true
    }

    override func responds(to selector: Selector?) -> Bool {
        if selector == #selector(NSResponder.performTextFinderAction(_:)) {
            return false
        }
        return super.responds(to: selector)
    }
}
