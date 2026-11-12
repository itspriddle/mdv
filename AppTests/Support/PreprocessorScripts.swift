import Darwin
import Foundation
import Testing

@testable import PeepApp

/// Custom preprocessor scripts (#57) for app tests, written into a test's folder with their
/// executable bit set. Scripts that start processes append their pids to `pidFile`, so a test
/// can check that every one of them is gone afterwards (`processesGone`).
struct PreprocessorScripts {
    let folder: URL

    /// Where scripts append the pids of the processes they start, one per line.
    var pidFile: URL { folder.appending(path: "preprocessor-pids") }

    /// Writes `/bin/sh` script `body` as `name` and returns its path.
    func write(_ name: String, _ body: String) throws -> String {
        let url = folder.appending(path: name)
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
        return url.path(percentEncoded: false)
    }

    /// The pid file's path, quoted for a script.
    private var quotedPidFile: String { "'\(pidFile.path(percentEncoded: false))'" }

    /// Upper-cases the document.
    func upcase() throws -> String {
        try write("upcase.sh", "tr '[:lower:]' '[:upper:]'")
    }

    /// Writes its arguments (one per line) and `PEEP_DOCUMENT_PATH` as a code block after the
    /// document.
    func report() throws -> String {
        try write(
            "report.sh",
            """
            cat
            printf '\\n```\\n'
            for argument in "$@"; do printf 'arg:%s\\n' "$argument"; done
            printf 'path:%s\\n' "$PEEP_DOCUMENT_PATH"
            printf '```\\n'
            """)
    }

    /// Writes to stderr and exits with status 3.
    func fail(stderr: String = "something went wrong") throws -> String {
        try write("fail.sh", "cat > /dev/null\necho '\(stderr)' >&2\nexit 3")
    }

    /// Hangs ignoring `SIGTERM`, so only the group's `SIGKILL` stops it.
    func hang() throws -> String {
        try write("hang.sh", "echo $$ >> \(quotedPidFile)\ntrap '' TERM\nwhile :; do sleep 1; done")
    }

    /// Sleeps `seconds`, then passes the document through.
    func slow(seconds: Double) throws -> String {
        try write("slow-\(seconds).sh", "echo $$ >> \(quotedPidFile)\nsleep \(seconds)\ncat")
    }

    /// Dies by `SIGSEGV`.
    func crash() throws -> String {
        try write("crash.sh", "ulimit -c 0\necho 'about to crash' >&2\nkill -SEGV $$")
    }

    /// Writes output forever (past the 10 MB limit).
    func flood() throws -> String {
        try write("flood.sh", "echo $$ >> \(quotedPidFile)\nexec yes 'A line of Markdown that goes on and on.'")
    }

    /// Starts a child that hangs ignoring `SIGTERM`, then passes the document through and
    /// exits 0, leaving the child in its process group.
    func fork() throws -> String {
        try write(
            "fork.sh",
            """
            sh -c 'trap "" TERM; while :; do sleep 1; done' &
            echo $$ >> \(quotedPidFile)
            echo $! >> \(quotedPidFile)
            sleep 0.1
            cat
            """)
    }

    /// Misbehaves according to the document: hangs ignoring `SIGTERM` if it contains `HANG`,
    /// dies by `SIGSEGV` on `CRASH`, floods stdout on `FLOOD`, exits 3 on `FAIL`, and otherwise
    /// passes it through. Lets a live reload switch one script between failures (#59).
    func modal() throws -> String {
        try write(
            "modal.sh",
            """
            echo $$ >> \(quotedPidFile)
            input=$(cat)
            case "$input" in
            *HANG*) trap '' TERM; while :; do sleep 1; done ;;
            *CRASH*) ulimit -c 0; kill -SEGV $$ ;;
            *FLOOD*) exec yes 'A line of Markdown that goes on and on.' ;;
            *FAIL*) echo 'failing on purpose' >&2; exit 3 ;;
            esac
            printf '%s\\n' "$input"
            """)
    }

    /// The pids scripts have written so far.
    func pids() -> [pid_t] {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8) else {
            return []
        }
        return text.split(whereSeparator: \.isWhitespace).compactMap { pid_t($0) }
    }

    /// Whether every process the scripts started is gone, and the app has no child processes
    /// left (the runner reaps each script), waiting up to `timeout`.
    func processesGone(timeout: Duration = .seconds(3)) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let pidsGone = pids().allSatisfy { kill($0, 0) != 0 && errno == ESRCH }
            if pidsGone, Self.childProcessCount() == 0 {
                return true
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    /// The app's own live child processes (zombies included).
    static func childProcessCount() -> Int {
        var pids = [pid_t](repeating: 0, count: 1024)
        let count = proc_listchildpids(getpid(), &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Int(max(count, 0))
    }

    /// An in-memory store with the preprocessor on, running `executable`.
    @MainActor
    static func settings(
        running executable: String, arguments: [String] = [], defaults: UserDefaults
    ) -> CustomPreprocessorSettings {
        let settings = CustomPreprocessorSettings(defaults: defaults, isPersistent: false)
        settings.executablePath = executable
        settings.arguments = arguments
        settings.isEnabled = true
        return settings
    }
}
