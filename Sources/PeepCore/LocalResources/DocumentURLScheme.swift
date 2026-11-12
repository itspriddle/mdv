import Foundation

/// The URL shape the app loads documents at, so relative URLs in a page resolve against the
/// document and every local read goes through the app's scheme handler (never `file:`).
///
///     peep-doc://<token>/<absolute file path, percent-encoded>
///
/// - `token` names one window's web view (random, lowercase). A handler answers only its own
///   token, so the host says which window a URL belongs to.
/// - The path is the file's absolute path, so `../x.png` and `docs/y.md` resolve exactly as
///   they would against a `file:` URL, and a resolved URL maps back to one file path.
///
/// The page itself is loaded at the document's URL (`url(token:filePath:)`); the scheme handler
/// serves only approved images (`LocalImagePolicy`) and answers 404 for everything else,
/// including the document URL.
public enum DocumentURLScheme {
    /// The custom URL scheme (`WKURLSchemeHandler`). Also named in the viewer CSP's `img-src`.
    public static let name = "peep-doc"

    /// A new random window token: a lowercase UUID.
    public static func makeToken() -> String {
        UUID().uuidString.lowercased()
    }

    /// The `peep-doc` URL for the file at absolute `filePath` in the window `token`. Returns nil
    /// for a relative or unclean path (see `filePath(from:token:)`).
    public static func url(token: String, filePath: String) -> URL? {
        guard let segments = segments(ofAbsolutePath: filePath) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = name
        components.host = token
        components.percentEncodedPath =
            "/"
            + segments.map { segment in
                segment.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? ""
            }
            .joined(separator: "/")
        return components.url
    }

    /// The `peep-doc` URL for the local `fileURL` in the window `token`.
    public static func url(token: String, fileURL: URL) -> URL? {
        guard fileURL.isFileURL else {
            return nil
        }
        return url(token: token, filePath: fileURL.path(percentEncoded: false))
    }

    /// The absolute file path that `url` names, if it is a `peep-doc` URL for the window
    /// `token`. The query and fragment are ignored.
    ///
    /// This is a lexical check only (no file system access): it refuses other schemes and
    /// tokens, user info and ports, and any path segment that is empty or that percent-decodes
    /// to `.`, `..`, or something containing `/` or NUL. WebKit already removes `.` and `..`
    /// when it resolves a relative URL; anything left is refused rather than reinterpreted.
    /// Callers that read files must still check the result against an allowed root
    /// (`LocalImagePolicy` does, after resolving symlinks).
    public static func filePath(from url: URL, token: String) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == name,
            components.percentEncodedHost?.lowercased() == token.lowercased(),
            components.percentEncodedUser == nil, components.percentEncodedPassword == nil,
            components.port == nil
        else {
            return nil
        }
        let encodedPath = components.percentEncodedPath
        guard encodedPath.hasPrefix("/") else {
            return nil
        }
        var decoded: [String] = []
        for encodedSegment in encodedPath.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
            guard let segment = String(encodedSegment).removingPercentEncoding, isPlainSegment(segment) else {
                return nil
            }
            decoded.append(segment)
        }
        return "/" + decoded.joined(separator: "/")
    }

    /// The local file or folder a link's `peep-doc` URL names, for the navigation policy: the
    /// same lexical rules as `filePath(from:token:)`, except that one trailing `/` is accepted
    /// and names a folder (`hasDirectoryPath`), as a link to `sub/` resolves. Image reads use
    /// `filePath(from:token:)`, which refuses folders.
    public static func fileURL(from url: URL, token: String) -> URL? {
        if let path = filePath(from: url, token: token) {
            return URL(filePath: path, directoryHint: .notDirectory)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.percentEncodedPath.count > 1, components.percentEncodedPath.hasSuffix("/")
        else {
            return nil
        }
        components.percentEncodedPath.removeLast()
        guard let folderURL = components.url, let path = filePath(from: folderURL, token: token) else {
            return nil
        }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    // MARK: Private

    /// RFC 3986 `pchar` minus `%`: unreserved, sub-delims, `:` and `@`. Everything else
    /// (including `/`, `?`, `#`, `%`, spaces, and non-ASCII) is percent-encoded.
    static let pathSegmentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@")

    private static func segments(ofAbsolutePath path: String) -> [String]? {
        guard path.hasPrefix("/") else {
            return nil
        }
        let segments = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard segments.allSatisfy(isPlainSegment) else {
            return nil
        }
        return segments
    }

    private static func isPlainSegment(_ segment: String) -> Bool {
        !segment.isEmpty && segment != "." && segment != ".." && !segment.contains("/") && !segment.contains("\0")
    }
}
