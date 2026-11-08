import MdvCore
import Observation

/// Feedback for slow renders (#58): what a window's progress indicator shows, after a delay.
///
/// - Until a window's first page has loaded (the document is still rendering, or a custom
///   preprocessor is still running), an indeterminate indicator shows in the middle of the blank
///   page, on the theme's background (`.firstPage`).
/// - While a newer render runs over a shown page (a live reload, a Settings change, a
///   preprocessor run), the old page stays and a small indicator shows in its corner
///   (`.update`).
///
/// Either shows only once the wait has lasted `delay` (300 ms), so normal opens and reloads
/// never flash it. It goes as soon as the wait ends: at the first page load, or when the newer
/// render lands. An indicator already showing changes kind at once (first page loaded while a
/// newer render runs) rather than waiting again.
@MainActor
@Observable
final class RenderProgress {
    enum Indicator: Equatable {
        /// Over the blank page, before the window's first page has loaded.
        case firstPage
        /// In the corner of the shown page, while a newer render runs.
        case update
    }

    /// How long a wait lasts before the indicator shows.
    static let defaultDelay: Duration = .milliseconds(300)

    /// The indicator to show, or nil for none.
    private(set) var indicator: Indicator?
    /// The window's theme background, so the indicator is drawn in the appearance that contrasts
    /// with it.
    var background: ThemeBackground

    /// How long a wait lasts before the indicator shows (tests inject their own).
    @ObservationIgnored let delay: Duration
    /// The indicator the current wait calls for, shown once `delay` has passed.
    @ObservationIgnored private(set) var pending: Indicator?
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(delay: Duration = defaultDelay, background: ThemeBackground = ThemeRegistry.bundled.defaultTheme.background) {
        self.delay = delay
        self.background = background
    }

    /// Reports the window's state: whether its first page is still to load, and whether its
    /// document is rendering (`MarkdownDocument.isRendering`).
    func update(isWaitingForFirstPage: Bool, isRendering: Bool) {
        let wanted: Indicator? = isWaitingForFirstPage ? .firstPage : isRendering ? .update : nil
        guard wanted != pending else {
            return
        }
        pending = wanted
        timer?.cancel()
        timer = nil
        guard let wanted else {
            indicator = nil
            return
        }
        if indicator != nil {
            indicator = wanted
            return
        }
        timer = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.pending == wanted else {
                return
            }
            self.indicator = wanted
        }
    }
}
