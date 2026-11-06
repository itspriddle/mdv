import SwiftUI

/// A bar above the page when the window isn't showing the file's current contents (deleted, or
/// a change that couldn't be read). Hidden while the file is current.
struct FileStatusBanner: View {
    let status: FileStatus

    var body: some View {
        if let message = status.message {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
                .accessibilityIdentifier("file-status-banner")
        }
    }
}
