import AppKit
import Darwin
import os

/// Cold-open timing for `scripts/measure-cold-open` (#40): milestones from process start to the
/// first painted page, written to standard error as one line of JSON.
///
/// Off unless the environment has `MDV_LAUNCH_TIMING` (`1` reports and keeps running, `exit`
/// reports and quits). It only reads clocks and prints numbers, so it stays in Release builds,
/// which are what the harness measures. Each mark costs one clock read when on, and one cached
/// `Bool` check when off.
///
/// Milestones are milliseconds since the kernel started the process (`kinfo_proc.p_starttime`),
/// so they include dyld and everything before `main`.
enum LaunchTiming {
    static let environmentKey = "MDV_LAUNCH_TIMING"

    /// Whether this launch is being measured.
    static let isEnabled = ProcessInfo.processInfo.environment[environmentKey] != nil
    /// Whether to quit after reporting, so the harness can launch again.
    static let quitsAfterReport = ProcessInfo.processInfo.environment[environmentKey] == "exit"

    private struct State {
        var marks: [(name: String, milliseconds: Double)] = []
        var hasReported = false
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// The process's start time, in seconds since 1970, from the kernel.
    private static let processStart: Double? = startTime(of: getpid())

    private static func startTime(of pid: pid_t) -> Double? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else {
            return nil
        }
        let start = info.kp_proc.p_un.__p_starttime
        return Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
    }

    /// Records `name` at the current time. The first mark of a name wins.
    static func mark(_ name: String) {
        guard isEnabled, let processStart else {
            return
        }
        var now = timeval()
        gettimeofday(&now, nil)
        let milliseconds = (Double(now.tv_sec) + Double(now.tv_usec) / 1_000_000 - processStart) * 1000
        state.withLock { state in
            guard !state.hasReported, !state.marks.contains(where: { $0.name == name }) else {
                return
            }
            state.marks.append((name, milliseconds))
        }
    }

    /// Marks `painted` once the page has drawn (two animation frames after its load finished),
    /// reports every mark, and quits if asked to. Only the first call reports.
    @MainActor
    static func firstPageLoaded(in coordinator: WebViewCoordinator) async {
        guard isEnabled, state.withLock({ !$0.hasReported }) else {
            return
        }
        try? await coordinator.waitForAnimationFrames(2)
        mark("painted")
        let marks = state.withLock { state in
            state.hasReported = true
            return state.marks
        }
        let fields = marks.map { #""\#($0.name)":\#(String(format: "%.1f", $0.milliseconds))"# }
        FileHandle.standardError.write(Data("mdv-launch-timing {\(fields.joined(separator: ","))}\n".utf8))
        if quitsAfterReport {
            NSApplication.shared.terminate(nil)
        }
    }
}
