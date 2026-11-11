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

    /// Waits up to 20 s for `pid` to exit (polling, so no thread blocks in `waitpid`).
    static func waitForExit(_ pid: pid_t) async throws -> ExitStatus {
        var status: Int32 = 0
        for _ in 0..<2000 {
            if waitpid(pid, &status, WNOHANG) == pid { return ExitStatus(raw: status) }
            try await Task.sleep(for: .milliseconds(10))
        }
        kill(pid, SIGKILL)
        _ = waitpid(pid, &status, 0)
        Issue.record("mdv didn't exit within 20 s")
        return ExitStatus(raw: status)
    }
}
