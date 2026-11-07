import Darwin
import Foundation

/// A hang detector: a main-actor loop that wakes every millisecond and records, between two
/// wake-ups, how long the main thread was away (`longestGap`, wall clock) and how much of that
/// it spent running (`longestBusyGap`, the main thread's CPU time).
///
/// `longestBusyGap` is the stall our code (or AppKit's) caused: it doesn't grow while the main
/// thread is merely descheduled, which is what a loaded machine (parallel builds, a slow CI
/// runner) adds to the wall clock. Assert tight bounds on it. A main thread blocked on a lock
/// or a synchronous wait uses no CPU, so keep a loose bound on `longestGap` as well: it catches
/// the main thread waiting for a render (hundreds of milliseconds), not scheduling noise.
@MainActor
final class MainThreadHeartbeat {
    private(set) var longestGap: Duration = .zero
    private(set) var longestBusyGap: Duration = .zero
    private var last = ContinuousClock.now
    private var lastCPU = MainThreadHeartbeat.threadCPUTime()
    private var task: Task<Void, Never>?

    func start() {
        reset()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1))
                self?.beat()
            }
        }
    }

    /// Forgets gaps so far; the next one is measured from now.
    func reset() {
        longestGap = .zero
        longestBusyGap = .zero
        last = ContinuousClock.now
        lastCPU = Self.threadCPUTime()
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func beat() {
        let now = ContinuousClock.now
        let cpu = Self.threadCPUTime()
        longestGap = max(longestGap, now - last)
        longestBusyGap = max(longestBusyGap, cpu - lastCPU)
        last = now
        lastCPU = cpu
    }

    /// The calling thread's CPU time (the main thread's, from the main actor).
    private static func threadCPUTime() -> Duration {
        .nanoseconds(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID))
    }
}
