import PeepCore
import SwiftUI

/// The bar above the page when the custom preprocessor failed (#57): the window shows the
/// document rendered without it, and the bar says why ("Preprocessor failed: The preprocessor
/// exited with status 2."). "Show Details" discloses the tail of the script's stderr. Never an
/// alert: a failing script is the reader's to fix, and every reload would raise another one.
///
/// Both texts come from the script (stderr) or name its path, so they are shown verbatim, never
/// read as Markdown.
struct PreprocessorFailureBar: View {
    let error: PreprocessorError
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(verbatim: "Preprocessor failed")
                    .fontWeight(.medium)
                Text(verbatim: error.message)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("preprocessor-failure-message")
                Spacer(minLength: 8)
                if !error.standardError.isEmpty {
                    Button(showsDetails ? "Hide Details" : "Show Details") {
                        showsDetails.toggle()
                    }
                    .controlSize(.small)
                    .help("Show what the preprocessor wrote to standard error.")
                    .accessibilityIdentifier("preprocessor-failure-details-button")
                }
            }
            Text(verbatim: "Showing the document without the preprocessor.")
                .foregroundStyle(.secondary)
            if showsDetails {
                ScrollView {
                    Text(verbatim: error.standardError)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .accessibilityIdentifier("preprocessor-failure-details")
                }
                .frame(maxHeight: 140)
                .background(.background.opacity(0.6), in: .rect(cornerRadius: 4))
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("preprocessor-failure-bar")
    }
}
