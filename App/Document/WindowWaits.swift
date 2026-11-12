import AppKit
import PeepCore
import notify

/// `peep --wait` (#69), the app's side: which windows each wait token is waiting on, and the
/// "windows closed" Darwin notification (`AppOpenEvent.windowsClosedNotificationName(for:)`)
/// once they have all closed. The CLI also watches the app's process, so a crash ends its wait.
///
/// `DocumentOpener` drives it: `begin` when an open event with a token arrives, `add` for each
/// window it opens or brings forward (an already-open file's window counts), `endOpening` when
/// every file has opened or failed. A token whose opening has ended with no open windows left
/// (all closed, or every file failed) is notified at once. Several tokens may share a window
/// (two `--wait`s on one file); closing it ends both. Standard input windows (#68) join a
/// token the same way, with `add`.
///
/// Tokens are untrusted (any process can send the open event), but all one can do is make the
/// app post a notification under Peep's prefix when windows close. Nothing is saved: a restored
/// window waits for no one, and quitting notifies every token (`notifyAll()`).
@MainActor
final class WindowWaits {
    private struct Wait {
        /// Open events with this token still opening files.
        var openings = 0
        var windows: [WeakWindow] = []
    }

    private struct WeakWindow {
        weak var window: NSWindow?
    }

    private var waits: [UUID: Wait] = [:]
    /// Posts the notification for a token; `notify_post` unless a test records it.
    private let post: @MainActor (UUID) -> Void

    init(post: (@MainActor (UUID) -> Void)? = nil) {
        self.post = post ?? { notify_post(AppOpenEvent.windowsClosedNotificationName(for: $0)) }
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: nil)
    }

    /// The tokens still waiting (tests).
    var pendingTokens: Set<UUID> { Set(waits.keys) }

    /// An open event carrying `token` started opening its files.
    func begin(_ token: UUID) {
        waits[token, default: Wait()].openings += 1
    }

    /// `windows` (a document's) now count for `token`.
    func add(_ windows: [NSWindow], to token: UUID) {
        guard var wait = waits[token] else {
            return
        }
        for window in windows where !wait.windows.contains(where: { $0.window === window }) {
            wait.windows.append(WeakWindow(window: window))
        }
        waits[token] = wait
    }

    /// An open event carrying `token` has opened (or failed to open) every file.
    func endOpening(_ token: UUID) {
        guard var wait = waits[token] else {
            return
        }
        wait.openings = max(0, wait.openings - 1)
        waits[token] = wait
        notifyFinished()
    }

    /// The app is quitting: every token's wait ends.
    func notifyAll() {
        let tokens = waits.keys
        waits.removeAll()
        for token in tokens {
            post(token)
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else {
            return
        }
        for token in waits.keys {
            waits[token]?.windows.removeAll { $0.window == nil || $0.window === closing }
        }
        notifyFinished()
    }

    /// Notifies and forgets each token that is done opening and has no open windows left.
    private func notifyFinished() {
        let finished = waits.filter { _, wait in
            // Not `isVisible`: a minimized window is still open.
            wait.openings == 0 && !wait.windows.contains { $0.window != nil }
        }.keys
        for token in finished {
            waits[token] = nil
            post(token)
        }
    }
}
