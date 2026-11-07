import AppKit

/// Starts the first window's web view at launch (#40), so its web content process launches
/// while the app finishes launching and reads the document, instead of after the window is
/// built.
///
/// A web view's first load waits for WebKit to launch its web content process, which took
/// 100-150 ms of the cold open (measured with `scripts/measure-cold-open`). Each `WKWebView` gets
/// its own process, so warming a separate web view doesn't help the window's: the warmed one has
/// to be the one the window shows. `prewarm()` makes a `WebViewCoordinator` and starts its
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
