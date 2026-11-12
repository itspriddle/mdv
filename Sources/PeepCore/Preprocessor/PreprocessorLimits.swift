/// The bounds on one custom preprocessor run (#56). `standard` is what the app uses; tests
/// inject shorter ones. Recorded in VISION's security model: change both together.
public struct PreprocessorLimits: Sendable, Equatable {
    /// Wall-clock time from launch until the script must have exited. A script that hangs,
    /// sleeps, or trickles output forever is stopped here.
    public var timeout: Duration
    /// Time between `SIGTERM` and `SIGKILL` when the process group is stopped (timeout, too
    /// much output, cancellation, or children left behind after the script exits).
    public var terminationGracePeriod: Duration
    /// The largest document passed on stdin; larger documents aren't run at all.
    public var maximumInputBytes: Int
    /// The most stdout kept; one byte more stops the script.
    public var maximumOutputBytes: Int
    /// The most stderr kept, from the end (the tail goes in the error message). More is read
    /// and dropped, never an error.
    public var maximumErrorBytes: Int

    public init(
        timeout: Duration,
        terminationGracePeriod: Duration,
        maximumInputBytes: Int,
        maximumOutputBytes: Int,
        maximumErrorBytes: Int
    ) {
        self.timeout = timeout
        self.terminationGracePeriod = terminationGracePeriod
        self.maximumInputBytes = maximumInputBytes
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumErrorBytes = maximumErrorBytes
    }

    /// 5 s, 0.5 s grace, 10 MB in and out (twice the largest document the app is measured
    /// with), 64 KB of stderr.
    public static let standard = PreprocessorLimits(
        timeout: .seconds(5),
        terminationGracePeriod: .milliseconds(500),
        maximumInputBytes: 10 * 1024 * 1024,
        maximumOutputBytes: 10 * 1024 * 1024,
        maximumErrorBytes: 64 * 1024
    )
}
