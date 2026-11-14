import SwiftUI

/// The strip along the bottom of a document window: quick facts about the document, leading,
/// and window toggles (pin, outline), trailing. Toggled with View > Show/Hide Status Bar.
///
/// Painted with the window's theme background (`WindowChrome`), under a border in the theme's
/// border color, so it blends with the page; its text and controls use the scheme that contrasts
/// with that background.
struct StatusBar: View {
    let document: MarkdownDocument
    let model: StatusBarModel
    let chrome: WindowChrome
    let toggleOutline: () -> Void
    let togglePinned: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = chrome.colors(in: colorScheme)
        VStack(spacing: 0) {
            ChromeBorder(chrome: chrome)
            HStack(spacing: 12) {
                WordCountItem(count: document.content?.page.wordCount)
                Spacer(minLength: 0)
                PinToggleItem(isPinned: model.isPinned, toggle: togglePinned)
                OutlineToggleItem(isOutlineVisible: model.isOutlineVisible, toggle: toggleOutline)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .environment(\.colorScheme, colors.contentScheme)
        }
        .background(Color(colors.background))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("status-bar")
    }
}

/// Shows or hides the outline sidebar, like View > Show/Hide Outline; tinted while it is shown.
struct OutlineToggleItem: View {
    let isOutlineVisible: Bool
    let toggle: () -> Void

    var body: some View {
        let title = isOutlineVisible ? "Hide Outline" : "Show Outline"
        Button(action: toggle) {
            Image(systemName: "list.bullet")
                .foregroundStyle(isOutlineVisible ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("outline-toggle")
    }
}

/// Pins or unpins the window (and its tabs), like Window > Pin/Unpin Window; filled and tinted
/// while pinned.
struct PinToggleItem: View {
    let isPinned: Bool
    let toggle: () -> Void

    var body: some View {
        let title = isPinned ? "Unpin Window" : "Pin Window"
        Button(action: toggle) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .foregroundStyle(isPinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(isPinned ? "on" : "off")
        .accessibilityIdentifier("pin-toggle")
    }
}

/// The document's word count (`RenderedPage.wordCount`); empty until the first render lands.
struct WordCountItem: View {
    let count: Int?

    var body: some View {
        if let count {
            let text = Self.text(for: count)
            Text(text)
                .monospacedDigit()
                .accessibilityIdentifier("word-count")
                .accessibilityLabel(text)
        }
    }

    /// "1 word", "1,340 words" (grouped for the reader's locale).
    static func text(for count: Int) -> String {
        count == 1 ? "1 word" : "\(count.formatted()) words"
    }
}
