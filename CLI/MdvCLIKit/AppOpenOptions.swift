import ArgumentParser

/// Flags for opening documents in the app (`mdv FILE` without an output flag): #67 (how the app
/// opens files), #69 (`--wait`). `AppOpening.open(_:options:)` receives this group.
public struct AppOpenOptions: ParsableArguments, Equatable, Sendable {
    public init() {}
}
