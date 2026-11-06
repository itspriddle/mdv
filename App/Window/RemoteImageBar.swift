import SwiftUI

/// The non-intrusive bar above the page when remote images are blocked (#20):
/// "Remote images blocked: 3 images from img.shields.io [Load]".
struct RemoteImageBar: View {
    let summary: RemoteImageSummary
    let load: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Remote images blocked")
                .fontWeight(.medium)
            Text(summary.detail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Button("Load", action: load)
                .controlSize(.small)
                .help("Load https images in this window. Nothing is remembered.")
                .accessibilityIdentifier("load-remote-images")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("remote-images-bar")
    }
}
