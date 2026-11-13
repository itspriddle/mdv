import SwiftUI

/// The strip along the bottom of a document window: quick facts about the document, leading,
/// and window toggles, trailing. Toggled with View > Show/Hide Status Bar.
struct StatusBar: View {
    let document: MarkdownDocument
    let model: StatusBarModel
    let toggleOutline: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                WordCountItem(count: document.content?.page.wordCount)
                Spacer(minLength: 0)
                OutlineToggleItem(isOutlineVisible: model.isOutlineVisible, toggle: toggleOutline)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 22)
        }
        .background(.bar)
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
