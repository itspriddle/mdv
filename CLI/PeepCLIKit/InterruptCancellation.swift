import Darwin
import Dispatch
import Synchronization

/// Runs work that must be stopped cleanly when the reader interrupts Peep (#66): Ctrl-C
/// (`SIGINT`), `SIGTERM`, or `SIGHUP` cancels the work, waits for it to finish, and then lets
/// the signal end the process as it would have, so the shell sees Peep killed by it.
///
/// The custom preprocessor runs in its own process group, so a terminal's Ctrl-C doesn't reach
/// it; without this, Peep would die and leave the script running. Cancelling
/// `CustomPreprocessor.run` stops the whole group and returns once it is reaped.
///
/// Only installed around the work (`CLIEnvironment.cancelsOnInterrupt`), so reading standard
/// input or writing output is still interrupted the default way. A signal the process was
/// started ignoring (`nohup`, a background job) stays ignored.
///
/// The signal is recorded by the handler itself, when it is delivered, not by the dispatch
/// source that cancels the work: the source's handler runs later on a queue, and a signal that
/// came while the run was ending (a timeout, say) would otherwise be lost when the sources are
/// dropped, and Peep would exit with the run's status instead of dying of the signal. One run at
/// a time (the CLI renders its inputs in turn).
enum InterruptCancellation {
    static let signals: [Int32] = [SIGINT, SIGTERM, SIGHUP]

    /// The first signal caught during the current run, or 0. Written only by `record`, the
    /// signal handler (an atomic store is async-signal-safe).
    private static let caught = Atomic<Int32>(0)

    /// The handler installed for each signal: records the first one. The dispatch source
    /// watching the same signal does the cancelling.
    private static let record: @convention(c) (Int32) -> Void = { number in
        _ = InterruptCancellation.caught.compareExchange(expected: 0, desired: number, ordering: .relaxed)
    }

    static func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let state = InterruptState()
        caught.store(0, ordering: .relaxed)
        var installed: [Installed] = []
        for number in signals {
            var previous = sigaction()
            guard sigaction(number, nil, &previous) == 0, !isIgnored(previous) else { continue }
            // The source first, then replace the default action: a signal in between still
            // ends the process, before any work has started.
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .userInitiated))
            // Record here too: the kernel reports the signal to the source when it is sent, and
            // may run the handler on a thread only later, after the cancelled run has ended
            // (seen on CI's macOS 26: Peep printed "interrupted" before the signal killed it).
            source.setEventHandler {
                _ = InterruptCancellation.caught.compareExchange(expected: 0, desired: number, ordering: .relaxed)
                state.received()
            }
            source.resume()
            var recording = sigaction()
            recording.__sigaction_u.__sa_handler = record
            sigemptyset(&recording.sa_mask)
            recording.sa_flags = SA_RESTART
            sigaction(number, &recording, nil)
            installed.append(Installed(signal: number, previous: previous, source: source))
        }

        let task = Task { try await operation() }
        state.setCancel { task.cancel() }
        let result = await withTaskCancellationHandler {
            await task.result
        } onCancel: {
            task.cancel()
        }

        // Restore before reading what was caught: a signal before this was recorded by the
        // handler, and one after it is handled the default way. No signal falls in between,
        // whether or not its source's event handler has run yet.
        for var entry in installed {
            sigaction(entry.signal, &entry.previous, nil)
            entry.source.cancel()
        }
        let number = caught.load(ordering: .relaxed)
        if number != 0 {
            // Even if the run finished first (it timed out, failed, or succeeded): the reader
            // asked Peep to stop. Ends the process; returns only if something else handles it.
            // Sent to the process, then wait for it: this code runs on a Swift concurrency
            // thread (a Darwin workqueue thread), which the kernel never delivers signals to,
            // so `raise` here could return with the signal undelivered and Peep would go on to
            // print "interrupted" (seen in the end-to-end test, about one run in four). The
            // kernel delivers a process-directed signal to a thread that takes it (the main
            // thread); this thread waits so nothing runs before it lands.
            kill(getpid(), number)
            for _ in 0..<100 { usleep(10_000) }
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

/// Whether a signal source fired and how to cancel the work, shared with the signal sources.
private final class InterruptState: Sendable {
    private struct Values: Sendable {
        var signaled = false
        var cancel: (@Sendable () -> Void)?
    }

    private let values = Mutex(Values())

    /// Notes that a signal came and cancels the work, if it has started.
    func received() {
        let cancel = values.withLock { values in
            values.signaled = true
            return values.cancel
        }
        cancel?()
    }

    /// Sets how to cancel the work; cancels at once if a signal already came.
    func setCancel(_ cancel: @escaping @Sendable () -> Void) {
        let signaled = values.withLock { values in
            values.cancel = cancel
            return values.signaled
        }
        if signaled { cancel() }
    }
}
