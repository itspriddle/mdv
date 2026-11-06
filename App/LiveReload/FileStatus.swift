import Foundation

/// How a document's window relates to its file on disk. Anything but `.current` means the window
/// keeps showing the last good render, with a banner (`FileStatusBanner`) saying why.
enum FileStatus: Equatable, Sendable {
    /// The window shows the file's current contents.
    case current
    /// The file was deleted (or moved to the Trash). mdv reloads if it reappears.
    case deleted
    /// The last change couldn't be read or isn't UTF-8; `reason` is shown to the user.
    case unreadable(reason: String)

    /// The banner text, or `nil` when there's nothing to say.
    var message: String? {
        switch self {
        case .current:
            nil
        case .deleted:
            "The file was deleted. Showing the last version; mdv reloads it if it comes back."
        case .unreadable(let reason):
            "Couldn't reload the file: \(reason) Showing the last version."
        }
    }
}
