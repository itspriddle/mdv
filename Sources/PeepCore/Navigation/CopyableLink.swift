import Foundation

/// What the viewer's context menu "Copy Link" puts on the pasteboard (#42).
///
/// Links in the viewer resolve against the page's `peep-doc://<token>/<path>` URL
/// (`DocumentURLScheme`), an internal URL that means nothing outside the window. A relative link
/// is copied as the `file:` URL of what it names, keeping its fragment, so it can be pasted into
/// a browser, Terminal, or another document. Every other URL (`https:`, `mailto:`, ...) is copied
/// as resolved. A `peep-doc` URL that names no file in this window is never copied.
public enum CopyableLink {
    /// The URL to copy for a link whose resolved URL is `url`, in the window `token`; `nil` to
    /// copy nothing. Never returns a `peep-doc` URL.
    public static func url(for url: URL, token: String) -> URL? {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            return nil
        }
        guard scheme == DocumentURLScheme.name else {
            return url
        }
        let fragment = url.fragment(percentEncoded: true)
        guard let target = url.withoutFragment, let file = DocumentURLScheme.fileURL(from: target, token: token)
        else {
            return nil
        }
        // Appended as text: `URLComponents.percentEncodedFragment` traps on an encoding it
        // doesn't accept, and the fragment comes from the document.
        let suffix = fragment.map { $0.isEmpty ? "" : "#" + $0 } ?? ""
        guard let copied = URL(string: file.absoluteString + suffix), copied.isFileURL else {
            return nil
        }
        return copied
    }
}
