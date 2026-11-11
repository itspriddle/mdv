import AppKit
import MdvCore

/// Feedback for slow renders (#58, `RenderProgress`): the window reports its state whenever the
/// document starts or stops rendering and when its first page loads, and fills the outline only
/// after that first page has painted.
extension DocumentWindowController {
    /// The longest the outline's first fill waits for the first page's frames. WebKit doesn't
    /// run animation frames for a window that isn't on screen (a background tab, a hidden
    /// window), and the outline must fill anyway.
    static let outlineFillFrameTimeout: Duration = .milliseconds(100)

    /// Called by `MarkdownDocument` when a render or live reload starts or ends.
    func renderActivityDidChange() {
        updateRenderProgress()
    }

    /// Passes the window's state to `renderProgress`.
    func updateRenderProgress() {
        renderProgress.update(
            isWaitingForFirstPage: isWaitingForFirstPage, isRendering: markdownDocument?.isRendering ?? false)
    }

    /// Fills the outline sidebar for the shown page once the first page has painted (two
    /// animation frames, or `outlineFillFrameTimeout`), so the fill (about 20 ms on main for a
    /// 5 MB document with the sidebar shown) isn't on the first paint's critical path. Later
    /// displays fill it as they show the page.
    func fillOutlineAfterFirstPaint() async {
        await waitForFrames(2, timeout: Self.outlineFillFrameTimeout)
        guard let page = displayedPage else {
            return
        }
        outlineController.show(DocumentOutline(headings: page.headings))
        await updateOutlinePosition()
    }

    /// Waits for `count` animation frames of the loaded page, or `timeout`, whichever is first.
    /// The frame request never holds the coordinator: a hidden or closed window runs no frames,
    /// and a request waiting on them forever would keep the web view, the window, and the
    /// document alive (`requestAnimationFrames(_:completion:)`).
    private func waitForFrames(_ count: Int, timeout: Duration) async {
        let waiter = FirstOf()
        await withCheckedContinuation { continuation in
            waiter.continuation = continuation
            coordinator.requestAnimationFrames(count) {
                waiter.resume()
            }
            Task {
                try? await Task.sleep(for: timeout)
                waiter.resume()
            }
        }
    }
}

/// Resumes a continuation once, for whichever of several tasks finishes first.
@MainActor
private final class FirstOf {
    var continuation: CheckedContinuation<Void, Never>?

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
