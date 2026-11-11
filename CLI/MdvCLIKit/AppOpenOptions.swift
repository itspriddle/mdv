import ArgumentParser

/// Flags for opening documents in the app (`mdv FILE` without an output flag): #67 (how the app
/// opens files), #69 (`--wait`). `AppOpening.open(_:options:)` receives this group.
public struct AppOpenOptions: ParsableArguments, Sendable {
    /// `--wait` (#69): return only once every window this run opened (or brought forward) is
    /// closed, or the app quits. Ctrl-C stops waiting and leaves the windows open.
    @Flag(help: "Wait until the windows mdv opens are closed (or the app quits).")
    public var wait = false

    public init() {}
}
