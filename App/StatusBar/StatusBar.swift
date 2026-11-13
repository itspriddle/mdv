import SwiftUI

/// The strip along the bottom of a document window: quick facts about the document, leading,
/// and (later) toggles. Toggled with View > Show/Hide Status Bar.
struct StatusBar: View {
    let document: MarkdownDocument

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                WordCountItem(count: document.content?.page.wordCount)
                Spacer(minLength: 0)
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
