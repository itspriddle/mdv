import Darwin
import Synchronization

/// Every file descriptor the preprocessor runner opens goes through here, so tests can check
/// that none outlive a run (`openCount`), whatever path the run took.
enum PreprocessorDescriptors {
    private static let open = Mutex<Set<Int32>>([])

    static var openCount: Int { open.withLock { $0.count } }

    static func track(_ descriptor: Int32) {
        open.withLock { _ = $0.insert(descriptor) }
    }

    /// Closes `descriptor` and sets it to -1; a no-op for -1.
    static func close(_ descriptor: inout Int32) {
        guard descriptor >= 0 else { return }
        open.withLock { _ = $0.remove(descriptor) }
        _ = Darwin.close(descriptor)
        descriptor = -1
    }
}

/// A launched preprocessor: its pid (also its process group id) and the parent's ends of its
/// stdin, stdout, and stderr pipes, all non-blocking and close-on-exec.
struct PreprocessorProcess {
    let pid: pid_t
    var standardInput: Int32
    var standardOutput: Int32
    var standardError: Int32

    /// Starts `executable` with `arguments` in its own process group.
    ///
    /// - `POSIX_SPAWN_SETPGROUP` (group 0) makes the child the leader of a new process group,
    ///   so stopping the run can signal every process the script started.
    /// - `POSIX_SPAWN_CLOEXEC_DEFAULT` gives the child only the three pipes as fds 0-2,
    ///   never another descriptor of the app's.
    /// - `POSIX_SPAWN_SETSIGDEF` and an empty mask give the child default signal handling
    ///   (the app may ignore `SIGPIPE`; a script expects it).
    /// - The stdin write end has `F_SETNOSIGPIPE`, so writing to a script that closed stdin
    ///   fails with `EPIPE` instead of raising `SIGPIPE` in Peep. This is per descriptor, so
    ///   the process-wide disposition is left alone.
    static func launch(
        executable: String,
        arguments: [String],
        environment: PreprocessorEnvironment
    ) throws(PreprocessorError) -> PreprocessorProcess {
        // Whatever isn't taken below (the child's ends, or everything on failure) is closed.
        var input = try Pipe()
        defer { input.closeAll() }
        var output = try Pipe()
        defer { output.closeAll() }
        var error = try Pipe()
        defer { error.closeAll() }
        let pid = try spawn(
            executable: executable,
            arguments: arguments,
            environment: environment,
            childDescriptors: [input.read, output.write, error.write]
        )
        let process = PreprocessorProcess(
            pid: pid,
            standardInput: input.takeWrite(),
            standardOutput: output.takeRead(),
            standardError: error.takeRead()
        )
        for descriptor in [process.standardInput, process.standardOutput, process.standardError] {
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        }
        _ = fcntl(process.standardInput, F_SETNOSIGPIPE, 1)
        return process
    }

    private static func spawn(
        executable: String,
        arguments: [String],
        environment: PreprocessorEnvironment,
        childDescriptors: [Int32]
    ) throws(PreprocessorError) -> pid_t {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        // The child's ends become its stdin, stdout, and stderr (0, 1, 2), in that order.
        for (target, descriptor) in childDescriptors.enumerated() {
            posix_spawn_file_actions_adddup2(&actions, descriptor, Int32(target))
        }
        if #available(macOS 26, *) {
            posix_spawn_file_actions_addchdir(&actions, environment.workingDirectory)
        } else {
            posix_spawn_file_actions_addchdir_np(&actions, environment.workingDirectory)
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(
            &attributes,
            Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        var defaults = sigset_t()
        sigfillset(&defaults)
        sigdelset(&defaults, SIGKILL)
        sigdelset(&defaults, SIGSTOP)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attributes, &mask)

        let argv = CStringArray([executable] + arguments)
        let envp = CStringArray(environment.variables)
        defer {
            argv.free()
            envp.free()
        }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, executable, &actions, &attributes, argv.pointers, envp.pointers)
        guard result == 0 else { throw PreprocessorError(.launchFailed(errno: result)) }
        return pid
    }
}

/// A pipe whose ends are tracked and close-on-exec. (macOS has no `pipe2`; another thread's
/// `fork` between `pipe` and `fcntl` could inherit an end, but `posix_spawn` users in this
/// process pass `POSIX_SPAWN_CLOEXEC_DEFAULT` or close extra descriptors themselves.)
private struct Pipe {
    var read: Int32 = -1
    var write: Int32 = -1

    init() throws(PreprocessorError) {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else { throw PreprocessorError(.launchFailed(errno: errno)) }
        read = descriptors[0]
        write = descriptors[1]
        for descriptor in descriptors {
            PreprocessorDescriptors.track(descriptor)
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        }
    }

    mutating func takeRead() -> Int32 {
        defer { read = -1 }
        return read
    }

    mutating func takeWrite() -> Int32 {
        defer { write = -1 }
        return write
    }

    mutating func closeAll() {
        PreprocessorDescriptors.close(&read)
        PreprocessorDescriptors.close(&write)
    }
}

/// A NULL-terminated array of C strings for `posix_spawn`; call `free()` when done.
private struct CStringArray {
    let pointers: [UnsafeMutablePointer<CChar>?]

    init(_ strings: [String]) {
        pointers = strings.map { strdup($0) } + [nil]
    }

    func free() {
        for pointer in pointers { Darwin.free(pointer) }
    }
}
