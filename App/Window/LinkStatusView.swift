import SwiftUI

/// The link status overlay at the bottom of a document window (like Safari's status bar):
/// where the hovered link goes, or a short message about the last link followed.
struct LinkStatusView: View {
    let status: LinkStatus

    var body: some View {
        if let text = status.text {
            Text(text)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
                .frame(maxWidth: 640, alignment: .leading)
                .padding(6)
                .allowsHitTesting(false)
                .accessibilityIdentifier("link-status")
                .accessibilityLabel(text)
        }
    }
}
