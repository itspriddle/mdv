import Darwin
import Dispatch
import Synchronization

/// Runs work that must be stopped cleanly when the reader interrupts mdv (#66): Ctrl-C
/// (`SIGINT`), `SIGTERM`, or `SIGHUP` cancels the work, waits for it to finish, and then lets
/// the signal end the process as it would have, so the shell sees mdv killed by it.
///
/// The custom preprocessor runs in its own process group, so a terminal's Ctrl-C doesn't reach
/// it; without this, mdv would die and leave the script running. Cancelling
/// `CustomPreprocessor.run` stops the whole group and returns once it is reaped.
///
/// Only installed around the work (`CLIEnvironment.cancelsOnInterrupt`), so reading standard
/// input or writing output is still interrupted the default way. A signal the process was
/// started ignoring (`nohup`, a background job) stays ignored.
enum InterruptCancellation {
    static let signals: [Int32] = [SIGINT, SIGTERM, SIGHUP]

    static func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let state = InterruptState()
        var installed: [Installed] = []
        for number in signals {
            var previous = sigaction()
            guard sigaction(number, nil, &previous) == 0, !isIgnored(previous) else { continue }
            // The source first, then ignore the default action: a signal in between still ends
            // the process, before any work has started.
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { state.received(number) }
            source.resume()
            var ignore = sigaction()
            ignore.__sigaction_u.__sa_handler = SIG_IGN
            sigaction(number, &ignore, nil)
            installed.append(Installed(signal: number, previous: previous, source: source))
        }

        let task = Task { try await operation() }
        state.setCancel { task.cancel() }
        let result = await withTaskCancellationHandler {
            await task.result
        } onCancel: {
            task.cancel()
        }

        // Restore before dropping the sources, so a late signal is handled the default way.
        for var entry in installed {
            sigaction(entry.signal, &entry.previous, nil)
            entry.source.cancel()
        }
        if let number = state.signal {
            raise(number)  // Ends the process; returns only if something else handles it.
        }
        return try result.get()
    }

    /// A signal handled during a run: its disposition before, to restore, and its source.
    private struct Installed {
        var signal: Int32
        var previous: sigaction
        var source: any DispatchSourceSignal
    }

    /// Whether `action` is `SIG_IGN`.
    private static func isIgnored(_ action: sigaction) -> Bool {
        unsafeBitCast(action.__sigaction_u.__sa_handler, to: Int.self) == unsafeBitCast(SIG_IGN, to: Int.self)
    }
}

/// The first signal received and how to cancel the work, shared with the signal sources.
private final class InterruptState: Sendable {
    private struct Values: Sendable {
        var signal: Int32?
        var cancel: (@Sendable () -> Void)?
    }

    private let values = Mutex(Values())

    var signal: Int32? { values.withLock { $0.signal } }

    /// Records `number` (the first one wins) and cancels the work, if it has started.
    func received(_ number: Int32) {
        let cancel = values.withLock { values in
            if values.signal == nil { values.signal = number }
            return values.cancel
        }
        cancel?()
    }

    /// Sets how to cancel the work; cancels at once if a signal already came.
    func setCancel(_ cancel: @escaping @Sendable () -> Void) {
        let signaled = values.withLock { values in
            values.cancel = cancel
            return values.signal != nil
        }
        if signaled { cancel() }
    }
}
