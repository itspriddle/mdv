import Darwin
import Foundation
import Testing

/// Runs a binary with SIGINT, SIGTERM, and SIGHUP at their default actions. A test runner (CI's)
/// may start with SIGINT ignored, and a spawned mdv rightly keeps an inherited `SIG_IGN`, so
/// signal tests can't use `Process`.
enum DefaultSignalProcess {
    /// Spawns `path` with SIGINT, SIGTERM, and SIGHUP reset to their default actions, standard
    /// input from /dev/null, standard output to `stdout`, and standard error to `stderr`.
    static func spawn(
        _ path: String, arguments: [String], environment: [String: String], stdout: String,
        stderr: String
    ) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in [SIGINT, SIGTERM, SIGHUP] { sigaddset(&defaults, signal) }
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, stdout, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_addopen(&actions, 2, stderr, O_WRONLY | O_CREAT | O_TRUNC, 0o600)

        let argv = ([path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, path, &actions, &attributes, argv, envp)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        return pid
    }

    /// How a spawned process ended: the signal that killed it, or its exit status.
    struct ExitStatus: CustomStringConvertible {
        let raw: Int32
        var signal: Int32? { raw & 0x7f == 0 ? nil : raw & 0x7f }
        var description: String { signal.map { "signal \($0)" } ?? "exit \((raw >> 8) & 0xff)" }
    }

    /// What `signal(_:whenFileAppears:)` saw.
    struct Interruption {
        /// The pids the program wrote, or `nil` if the file never appeared.
        var pids: [pid_t]?
        /// Whether the process had already exited when the signal was due (so it wasn't sent).
        var exitedBeforeSignal: Bool
        var status: ExitStatus
        /// From `start` to the process's exit, as seen by a thread that polls every 10 ms.
        var elapsed: Duration
    }

    /// Waits for `path` to hold a line of pids, sends `signal` to `pid`, and waits for `pid` to
    /// exit (killing it after `limit`). All on a dedicated thread: on a test runner whose
    /// cooperative pool is busy (other tests blocking it in `waitUntilExit`, a starved CI
    /// runner), an async task polling the file got to send the signal 30 s late, long after the
    /// program it was meant to interrupt had timed out.
    static func signal(
        _ signal: Int32, _ pid: pid_t, whenFileAppears path: String, start: ContinuousClock.Instant,
        limit: Duration
    ) async -> Interruption {
        await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: interrupt(pid, signal, path: path, start: start, limit: limit))
            }
            thread.name = "mdv-tests.signal"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    private static func interrupt(
        _ pid: pid_t, _ signal: Int32, path: String, start: ContinuousClock.Instant, limit: Duration
    ) -> Interruption {
        var status: Int32 = 0
        var pids: [pid_t]?
        var exitedBeforeSignal = false
        while ContinuousClock.now - start < limit {
            if waitpid(pid, &status, WNOHANG) == pid {
                exitedBeforeSignal = true
                break
            }
            if let text = try? String(contentsOfFile: path, encoding: .utf8), text.hasSuffix("\n") {
                pids = text.split(whereSeparator: \.isWhitespace).compactMap { pid_t($0) }
                kill(pid, signal)
                break
            }
            usleep(10_000)
        }
        if !exitedBeforeSignal {
            while waitpid(pid, &status, WNOHANG) != pid {
                if ContinuousClock.now - start >= limit {
                    kill(pid, SIGKILL)
                    _ = waitpid(pid, &status, 0)
                    break
                }
                usleep(10_000)
            }
        }
        return Interruption(
            pids: pids, exitedBeforeSignal: exitedBeforeSignal, status: ExitStatus(raw: status),
            elapsed: ContinuousClock.now - start)
    }
}
