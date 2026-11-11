import Darwin
import Dispatch
import Foundation
import MdvCore
import Synchronization
import notify

/// `mdv --wait` (#69): waits for the app to say the windows of one open event have closed, or
/// for the app's process to exit (quit, crash, force quit), whichever comes first.
///
/// Create it before sending the open event, so a window closed at once isn't missed: it
/// registers for the Darwin notification named for its `token`
/// (`AppOpenEvent.windowsClosedNotificationName(for:)`), which the app posts. Darwin
/// notifications (`notify(3)`) arrive on a dispatch queue, so no run loop is needed. Any process
/// can post one, so a forged notification only ends the wait early (VISION, "CLI to app").
///
/// Ctrl-C is left to its default action: it ends mdv, and the windows stay open.
final class WindowsClosedWaiter: Sendable {
    /// The random token for this invocation, sent to the app as `AppOpenParameters.waitToken`.
    let token: UUID

    private let core: Core
    private let registration: Int32

    /// Registers for `token`'s notification; `ExitStatus.unavailable` if that fails (nothing has
    /// opened yet).
    init(token: UUID = UUID()) throws(CLIError) {
        let core = Core()
        var registration: Int32 = 0
        let status = notify_register_dispatch(
            AppOpenEvent.windowsClosedNotificationName(for: token), &registration, core.queue
        ) { _ in core.finish() }
        guard status == NOTIFY_STATUS_OK else {
            throw CLIError(
                "couldn't wait for the app's windows (notify status \(status))", status: ExitStatus.unavailable)
        }
        self.token = token
        self.core = core
        self.registration = registration
    }

    deinit {
        notify_cancel(registration)
        core.cancelProcessSource()
    }

    /// Returns once the notification arrives (even if it already did), the process
    /// `processIdentifier` exits (or is already gone), or the task is cancelled.
    func wait(forProcess processIdentifier: pid_t?) async {
        if let processIdentifier {
            core.watch(processIdentifier)
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                core.setContinuation(continuation)
            }
        } onCancel: {
            core.finish()
        }
        core.cancelProcessSource()
    }

    /// Whether the wait has ended (tests).
    var isFinished: Bool { core.isFinished }
}

/// The waiter's state, shared with the notification and process handlers.
private final class Core: Sendable {
    private struct State: @unchecked Sendable {
        var isFinished = false
        var continuation: CheckedContinuation<Void, Never>?
        var processSource: (any DispatchSourceProcess)?
    }

    let queue = DispatchQueue(label: "mdv.wait")
    private let state = Mutex(State())

    var isFinished: Bool { state.withLock { $0.isFinished } }

    /// Ends the wait: resumes the waiting task, now or as soon as it waits.
    func finish() {
        let continuation = state.withLock { state in
            state.isFinished = true
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume()
    }

    func setContinuation(_ continuation: CheckedContinuation<Void, Never>) {
        let finished = state.withLock { state in
            if !state.isFinished {
                state.continuation = continuation
            }
            return state.isFinished
        }
        if finished {
            continuation.resume()
        }
    }

    /// Finishes when `processIdentifier` exits. Checked again after the source is set up: a
    /// kqueue filter can't be added for a process that is already gone.
    func watch(_ processIdentifier: pid_t) {
        let source = DispatchSource.makeProcessSource(identifier: processIdentifier, eventMask: .exit, queue: queue)
        source.setEventHandler { [weak self] in self?.finish() }
        state.withLock { $0.processSource = source }
        source.resume()
        if kill(processIdentifier, 0) != 0, errno == ESRCH {
            finish()
        }
    }

    func cancelProcessSource() {
        let source = state.withLock { state in
            defer { state.processSource = nil }
            return state.processSource
        }
        source?.cancel()
    }
}
