import Foundation
import Testing

/// Main-thread timing checks (`MainThreadHeartbeat` bounds, first-render and close times): strict
/// by default, report-only when `PEEP_TIMING_REPORT_ONLY=1` (CI sets it, as
/// `TEST_RUNNER_PEEP_TIMING_REPORT_ONLY`, because `xcodebuild` forwards only `TEST_RUNNER_`
/// variables to the test process).
///
/// Why: shared macOS runners are often starved. M4's close-out saw main-thread gaps of
/// 0.26-0.67 s with almost no CPU used, and busy times of 18-27 ms on code that measures
/// 1.3-1.5 ms on a real Mac, even with every core loaded. On CI a miss is recorded as a known
/// issue with the measured value, so the numbers stay in the log without failing the run;
/// locally the bound fails the test.
enum MainThreadTiming {
    static var isReportOnly: Bool {
        ProcessInfo.processInfo.environment["PEEP_TIMING_REPORT_ONLY"] == "1"
    }
}

/// `#expect(condition)` for a main-thread timing bound; see `MainThreadTiming`.
func expectTiming(
    _ condition: Bool, _ comment: @autoclosure () -> Comment, sourceLocation: SourceLocation = #_sourceLocation
) {
    guard MainThreadTiming.isReportOnly else {
        #expect(condition, comment(), sourceLocation: sourceLocation)
        return
    }
    withKnownIssue("timing is report-only on CI (PEEP_TIMING_REPORT_ONLY)", isIntermittent: true) {
        #expect(condition, comment(), sourceLocation: sourceLocation)
    }
}
