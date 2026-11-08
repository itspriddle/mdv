import Darwin
import Synchronization

/// One preprocessor run's I/O, driven on a dedicated thread (never the cooperative pool) by a
/// single kqueue: stdin writes, stdout and stderr reads, the script's exit, a cancellation
/// event, and the deadline, all in one loop, so nothing can deadlock on a full pipe.
///
/// Stopping (timeout, too much output, cancellation) sends `SIGTERM` to the process group,
/// waits up to the grace period for the script to exit, then sends `SIGKILL` to the group.
/// When the script exits on its own, anything it left in its group gets the same treatment
/// (`SIGTERM`, then `SIGKILL` once the pipes close or the grace period ends). The script is
/// reaped only after the group's last `SIGKILL`, so its process group id can't be reused by
/// an unrelated process while it is being signaled. A process that left the group (`setsid`)
/// is out of reach; the pipes stop being read after the grace period either way.
final class PreprocessorSession: Sendable {
    enum Stop: Equatable, Sendable {
        case timedOut
        case outputTooLarge
        case cancelled
    }

    struct Outcome: Sendable {
        var output: [UInt8]
        var errorTail: [UInt8]
        /// The `waitpid` status.
        var status: Int32
        var stop: Stop?
    }

    private static let cancelEvent: UInt = 1

    private struct Shared {
        var queue: Int32
        var cancelled = false
    }

    private let shared: Mutex<Shared>
    private let limits: PreprocessorLimits

    init(limits: PreprocessorLimits) throws(PreprocessorError) {
        let queue = kqueue()
        guard queue >= 0 else { throw PreprocessorError(.launchFailed(errno: errno)) }
        PreprocessorDescriptors.track(queue)
        _ = fcntl(queue, F_SETFD, FD_CLOEXEC)
        var change = kevent(
            ident: Self.cancelEvent, filter: Int16(EVFILT_USER), flags: UInt16(EV_ADD | EV_CLEAR), fflags: 0, data: 0,
            udata: nil)
        _ = kevent(queue, &change, 1, nil, 0, nil)
        self.shared = Mutex(Shared(queue: queue))
        self.limits = limits
    }

    /// Wakes the loop to stop the run; safe from any thread, before, during, or after it.
    func cancel() {
        shared.withLock { state in
            state.cancelled = true
            guard state.queue >= 0 else { return }
            var change = kevent(
                ident: Self.cancelEvent, filter: Int16(EVFILT_USER), flags: 0, fflags: UInt32(NOTE_TRIGGER), data: 0,
                udata: nil)
            _ = kevent(state.queue, &change, 1, nil, 0, nil)
        }
    }

    var isCancelled: Bool { shared.withLock { $0.cancelled } }

    /// Releases the kqueue. Call once, after `drive` returns (or instead of it).
    func finish() {
        shared.withLock { state in
            PreprocessorDescriptors.close(&state.queue)
        }
    }

    private var queue: Int32 { shared.withLock { $0.queue } }

    /// Feeds `input` to `process`, collects its output, and returns once it has been reaped.
    /// Every descriptor of `process` is closed on return.
    func drive(_ process: PreprocessorProcess, input: [UInt8]) -> Outcome {
        var loop = Loop(process: process, input: input, limits: limits, queue: queue)
        if isCancelled { loop.stop(.cancelled) }
        loop.run()
        return loop.finish()
    }
}

/// The loop's state, confined to the session's thread.
private struct Loop {
    var process: PreprocessorProcess
    let input: [UInt8]
    let limits: PreprocessorLimits
    let queue: Int32
    static let chunkSize = 64 * 1024

    let clock = ContinuousClock()
    let deadline: ContinuousClock.Instant

    var written = 0
    var output: [UInt8] = []
    var errorTail: [UInt8] = []
    var exited = false
    var stopReason: PreprocessorSession.Stop?
    var terminatedAt: ContinuousClock.Instant?

    init(process: PreprocessorProcess, input: [UInt8], limits: PreprocessorLimits, queue: Int32) {
        self.process = process
        self.input = input
        self.limits = limits
        self.queue = queue
        self.deadline = ContinuousClock.now.advanced(by: limits.timeout)
        register()
    }

    private mutating func register() {
        var changes = [
            Self.event(process.standardOutput, EVFILT_READ, EV_ADD),
            Self.event(process.standardError, EVFILT_READ, EV_ADD),
            kevent(
                ident: UInt(process.pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ONESHOT),
                fflags: UInt32(NOTE_EXIT), data: 0, udata: nil),
        ]
        if input.isEmpty {
            PreprocessorDescriptors.close(&process.standardInput)
        } else {
            changes.append(Self.event(process.standardInput, EVFILT_WRITE, EV_ADD))
        }
        for var change in changes {
            // ESRCH for the process means it already exited: the pid is a zombie until reaped,
            // so check for that instead of waiting for an event that won't come.
            if kevent(queue, &change, 1, nil, 0, nil) < 0, change.filter == Int16(EVFILT_PROC) {
                exited = true
            }
        }
    }

    private static func event(_ descriptor: Int32, _ filter: Int32, _ flags: Int32) -> kevent {
        kevent(ident: UInt(descriptor), filter: Int16(filter), flags: UInt16(flags), fflags: 0, data: 0, udata: nil)
    }

    private var pipesClosed: Bool { process.standardOutput < 0 && process.standardError < 0 }

    mutating func run() {
        var events = Array(repeating: kevent(), count: 8)
        while true {
            let now = clock.now
            if stopReason == nil, !exited, now >= deadline { stop(.timedOut) }
            if exited, terminatedAt == nil { terminate() }  // reap leftovers in the group
            if let terminatedAt, now >= terminatedAt.advanced(by: limits.terminationGracePeriod) { return }
            if exited, stopReason != nil || pipesClosed { return }

            var timeout = Self.timespec(until: nextWake, from: now)
            let count = kevent(queue, nil, 0, &events, Int32(events.count), &timeout)
            guard count >= 0 else {
                if errno == EINTR { continue }
                stop(.cancelled)  // the queue is unusable; stop the script rather than spin
                return
            }
            for event in events.prefix(Int(count)) { handle(event) }
        }
    }

    private var nextWake: ContinuousClock.Instant {
        if let terminatedAt { return terminatedAt.advanced(by: limits.terminationGracePeriod) }
        return deadline
    }

    private static func timespec(until wake: ContinuousClock.Instant, from now: ContinuousClock.Instant) -> timespec {
        let remaining = max(.zero, now.duration(to: wake))
        let (seconds, attoseconds) = remaining.components
        return Darwin.timespec(tv_sec: Int(seconds), tv_nsec: Int(attoseconds / 1_000_000_000))
    }

    private mutating func handle(_ event: kevent) {
        switch Int32(event.filter) {
        case EVFILT_PROC: exited = true
        case EVFILT_USER: stop(.cancelled)
        case EVFILT_WRITE: writeInput()
        case EVFILT_READ:
            if Int32(event.ident) == process.standardOutput {
                readOutput()
            } else if Int32(event.ident) == process.standardError {
                readError()
            }
        default: break
        }
    }

    private mutating func writeInput() {
        guard process.standardInput >= 0 else { return }
        let count = input.withUnsafeBytes { bytes in
            Darwin.write(
                process.standardInput, bytes.baseAddress?.advanced(by: written),
                min(bytes.count - written, Self.chunkSize))
        }
        if count > 0 { written += count }
        // EPIPE: the script closed stdin. Not an error; it may not need the rest.
        if written == input.count || (count < 0 && errno != EAGAIN && errno != EINTR) {
            PreprocessorDescriptors.close(&process.standardInput)
        }
    }

    private mutating func readOutput() {
        guard let chunk = Self.read(&process.standardOutput) else { return }
        guard stopReason == nil else { return }  // still drained, so the script isn't blocked
        output.append(contentsOf: chunk)
        if output.count > limits.maximumOutputBytes { stop(.outputTooLarge) }
    }

    private mutating func readError() {
        guard let chunk = Self.read(&process.standardError) else { return }
        errorTail.append(contentsOf: chunk)
        if errorTail.count > 2 * limits.maximumErrorBytes {
            errorTail.removeFirst(errorTail.count - limits.maximumErrorBytes)
        }
    }

    /// One read; closes the descriptor at end of file or on an error. `nil` when nothing was read.
    private static func read(_ descriptor: inout Int32) -> [UInt8]? {
        guard descriptor >= 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Self.chunkSize)
        let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
        if count > 0 { return Array(buffer.prefix(count)) }
        if count == 0 || (errno != EAGAIN && errno != EINTR) {
            PreprocessorDescriptors.close(&descriptor)
        }
        return nil
    }

    mutating func stop(_ reason: PreprocessorSession.Stop) {
        if stopReason == nil { stopReason = reason }
        terminate()
    }

    private mutating func terminate() {
        guard terminatedAt == nil else { return }
        terminatedAt = clock.now
        _ = killpg(process.pid, SIGTERM)
    }

    /// Kills whatever is left in the group, closes the pipes, and reaps the script.
    mutating func finish() -> PreprocessorSession.Outcome {
        _ = killpg(process.pid, SIGKILL)
        PreprocessorDescriptors.close(&process.standardInput)
        PreprocessorDescriptors.close(&process.standardOutput)
        PreprocessorDescriptors.close(&process.standardError)
        var status: Int32 = 0
        while waitpid(process.pid, &status, 0) < 0, errno == EINTR {}
        return PreprocessorSession.Outcome(
            output: output, errorTail: Array(errorTail.suffix(limits.maximumErrorBytes)), status: status,
            stop: stopReason)
    }
}
