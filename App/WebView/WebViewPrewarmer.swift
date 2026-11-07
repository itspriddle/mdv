import AppKit

/// Starts the first window's web view at launch (#40), so its web content process launches
/// while the app finishes launching and reads the document, instead of after the window is
/// built.
///
/// A web view's first load waits for WebKit to start its web content process: about 130 ms
/// from `loadHTMLString` to a finished page in a bare app (`scripts/measure-cold-open -f`), on
/// the critical path when the window started it after the launch and the document read. Each
/// `WKWebView` gets its own process, so warming a separate web view doesn't help the window's:
/// the warmed one has to be the one the window shows.
///
/// If no document window opens (the Open panel is cancelled), the spare stays until one does. `prewarm()` makes a `WebViewCoordinator` and starts its
/// preparation load (`prepareForFirstLoad()`); the first document window takes it with
/// `takeCoordinator()`. Later windows make their own, as before.
@MainActor
final class WebViewPrewarmer {
    static let shared = WebViewPrewarmer()

    private var spare: WebViewCoordinator?
    private var hasPrewarmed = false

    /// Makes and prepares the coordinator the first window will use. Once per launch.
    func prewarm() {
        guard !hasPrewarmed else {
            return
        }
        hasPrewarmed = true
        let coordinator = WebViewCoordinator()
        coordinator.prepareForFirstLoad()
        spare = coordinator
    }

    /// The prewarmed coordinator if there is one (the first window), else a new one.
    func takeCoordinator() -> WebViewCoordinator {
        guard let spare else {
            return WebViewCoordinator()
        }
        self.spare = nil
        return spare
    }
}
