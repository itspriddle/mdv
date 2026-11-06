import AppKit
import UniformTypeIdentifiers

/// The Launch Services calls mdv makes to read and change the default app for a content type.
///
/// `NSWorkspace` changes the user's real system defaults, so tests use a fake.
@MainActor
protocol DefaultApplicationWorkspace {
    /// The bundle identifier of the app that opens `contentType` by default, if any.
    func defaultApplicationBundleIdentifier(toOpen contentType: UTType) -> String?

    /// Makes the app at `applicationURL` the default for `contentType`. macOS may ask the user to
    /// confirm; declining throws.
    func setDefaultApplication(at applicationURL: URL, toOpen contentType: UTType) async throws
}

/// `DefaultApplicationWorkspace` backed by `NSWorkspace`.
struct SystemDefaultApplicationWorkspace: DefaultApplicationWorkspace {
    func defaultApplicationBundleIdentifier(toOpen contentType: UTType) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: contentType) else {
            return nil
        }
        return Bundle(url: url)?.bundleIdentifier
    }

    func setDefaultApplication(at applicationURL: URL, toOpen contentType: UTType) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: applicationURL, toOpen: contentType)
    }
}
