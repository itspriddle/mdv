import SwiftUI

/// The window's render progress indicator (#58), overlaid on the web view: a spinner in the
/// middle of the blank page before the first page loads, or a small one in the top corner while
/// a newer render runs over the shown page. It never takes clicks.
struct RenderProgressIndicator: View {
    let progress: RenderProgress

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch progress.indicator {
        case .firstPage:
            ProgressView()
                .controlSize(.regular)
                // On the theme's background, which needn't follow the system appearance.
                .environment(\.colorScheme, backgroundScheme)
                .accessibilityLabel("Rendering")
                .accessibilityIdentifier("render-progress")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        case .update:
            ProgressView()
                .controlSize(.small)
                .padding(6)
                .background(.regularMaterial, in: Circle())
                .accessibilityLabel("Updating")
                .accessibilityIdentifier("render-progress-update")
                .padding(.top, 10)
                // Clear of the vertical scroller.
                .padding(.trailing, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)
        case nil:
            EmptyView()
        }
    }

    /// The appearance that contrasts with the theme's background in the current one.
    private var backgroundScheme: ColorScheme {
        let color = colorScheme == .dark ? progress.background.dark : progress.background.light
        return color.isDark ? .dark : .light
    }
}
