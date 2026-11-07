import Foundation

/// Root-relative URLs (`/docs/x.png`), resolved the way GitHub does: against the repository
/// root, not the file system root (`RenderOptions.linkRoot`).
///
/// The renderer rewrites such a URL to `<root>/docs/x.png`, the folder's absolute path
/// (percent-encoded) followed by the URL's path, query, and fragment. The page is loaded at the
/// document's absolute path (`DocumentURLScheme`), so the rewritten URL resolves to the file
/// under the root, and links and images go through their usual checks unchanged
/// (`LocalImagePolicy` stays the authority on what is read; `LinkPolicy` on what is opened).
///
/// - Only a single leading `/` counts. `//host` and `/\host` are scheme-relative (remote) and are
///   left alone, as are relative paths, `#fragment`, `?query`, and URLs with a scheme.
/// - The root is the top: `.` and `..` segments (also spelled `%2e`) are removed as a URL parser
///   would, but `..` never goes above the root, so `/../x.png` names `<root>/x.png`. The result
///   never starts with `//`, even for the root `/`.
/// - Other percent-encoded segments are kept as written; `DocumentURLScheme` refuses any that
///   decode to `/` or NUL.
public enum RootRelativeURL {
    /// The rewritten URL for `url` under the folder `root` (an absolute path), or nil when
    /// `url` isn't root-relative. The result is unescaped for HTML: callers write it like any
    /// other URL (`HTMLOutput.url`). Tab and newlines are removed and the ends trimmed first,
    /// as a URL parser does.
    public static func resolve(_ url: String, root: String) -> String? {
        guard root.hasPrefix("/") else {
            return nil
        }
        let cleaned = cleaned(url)
        let scalars = cleaned.unicodeScalars
        guard scalars.first == "/" else {
            return nil
        }
        if scalars.count > 1 {
            let second = scalars[scalars.index(after: scalars.startIndex)]
            guard second != "/", second != "\\" else {
                return nil
            }
        }
        let pathEnd = cleaned.firstIndex { $0 == "?" || $0 == "#" } ?? cleaned.endIndex
        let path = removingDotSegments(cleaned[..<pathEnd])
        return encodedPath(of: root) + path + cleaned[pathEnd...]
    }

    /// `url` as a URL parser reads it: tab, LF, and CR removed everywhere, and leading and
    /// trailing C0 controls and spaces trimmed.
    static func cleaned(_ url: String) -> String {
        var scalars = url.unicodeScalars.filter { $0 != "\t" && $0 != "\n" && $0 != "\r" }
        while let first = scalars.first, first.value <= 0x20 {
            scalars.removeFirst()
        }
        while let last = scalars.last, last.value <= 0x20 {
            scalars.removeLast()
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// RFC 3986 `remove_dot_segments` for an absolute path, with `..` clamped at the top.
    private static func removingDotSegments(_ path: Substring) -> String {
        let segments = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        var output: [Substring] = []
        for (index, segment) in segments.enumerated() {
            let isLast = index == segments.count - 1
            switch segment.lowercased() {
            case ".", "%2e":
                break
            case "..", ".%2e", "%2e.", "%2e%2e":
                if !output.isEmpty {
                    output.removeLast()
                }
            default:
                output.append(segment)
                continue
            }
            // A trailing `.` or `..` names a folder: keep the trailing slash.
            if isLast {
                output.append("")
            }
        }
        // `/.//host` or `/..//host` would otherwise start with `//`, which is scheme-relative
        // (remote) when the root is `/`.
        while output.count > 1, output[0].isEmpty {
            output.removeFirst()
        }
        return "/" + output.joined(separator: "/")
    }

    /// `root` percent-encoded segment by segment (`%` included), without a trailing slash; empty
    /// for `/`.
    private static func encodedPath(of root: String) -> String {
        root.split(separator: "/").map { segment in
            "/" + (segment.addingPercentEncoding(withAllowedCharacters: DocumentURLScheme.pathSegmentAllowed) ?? "")
        }
        .joined()
    }
}
