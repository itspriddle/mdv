import Foundation
import Testing

/// Wall-clock bounds on large renders (`StressTests`): strict by default, report-only when
/// `MDV_TIMING_REPORT_ONLY=1` (CI's core test step sets it), as for the app's main-thread bounds
/// (`AppTests/Support/MainThreadTiming.swift`).
///
/// Why: on CI's shared macOS 26 runners the 8 MB render took 21.1-21.5 s against a 20 s bound
/// while the CLI suite's processes ran beside it (M5). On CI a miss is recorded as a known issue
/// with the measured value; locally the bound fails the test. Correctness checks stay strict.
func expectRenderTiming(
    _ condition: Bool, _ comment: @autoclosure () -> Comment, sourceLocation: SourceLocation = #_sourceLocation
) {
    guard ProcessInfo.processInfo.environment["MDV_TIMING_REPORT_ONLY"] == "1" else {
        #expect(condition, comment(), sourceLocation: sourceLocation)
        return
    }
    withKnownIssue("timing is report-only on CI (MDV_TIMING_REPORT_ONLY)", isIntermittent: true) {
        #expect(condition, comment(), sourceLocation: sourceLocation)
    }
}
