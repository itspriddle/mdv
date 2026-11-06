/// A UTF-8 byte buffer with cmark-compatible HTML escaping helpers.
struct HTMLOutput {
    private(set) var bytes: [UInt8] = []

    init(capacity: Int = 0) {
        bytes.reserveCapacity(capacity)
    }

    /// The output as a string. Always valid UTF-8: only whole strings and ASCII are appended.
    var string: String {
        String(validating: bytes, as: UTF8.self) ?? ""
    }

    /// Appends trusted markup verbatim.
    mutating func raw(_ markup: String) {
        bytes.append(contentsOf: markup.utf8)
    }

    mutating func raw(_ byte: UInt8) {
        bytes.append(byte)
    }

    /// Starts a new line unless the output is empty or already at one (cmark's `cr`).
    mutating func newlineIfNeeded() {
        if let last = bytes.last, last != Self.newline {
            bytes.append(Self.newline)
        }
    }

    /// Escapes text for element content and quoted attribute values, like cmark's
    /// `houdini_escape_html0(…, secure: 0)`: `& < > "` are escaped; `'` and `/` are not.
    mutating func text(_ text: String) {
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "&"): raw("&amp;")
            case UInt8(ascii: "<"): raw("&lt;")
            case UInt8(ascii: ">"): raw("&gt;")
            case UInt8(ascii: "\""): raw("&quot;")
            default: bytes.append(byte)
            }
        }
    }

    /// Percent-encodes a URL for an `href`/`src` attribute, like cmark's `houdini_escape_href`.
    ///
    /// Alphanumerics and `-_.+!*(),%#@?=;:/$~` pass through, `&` and `'` become entities, and
    /// every other byte (including non-ASCII UTF-8) becomes `%XX`. Existing `%XX` sequences are
    /// left alone, so already-encoded URLs are not double-encoded.
    mutating func url(_ url: String) {
        for byte in url.utf8 {
            if Self.isHrefSafe(byte) {
                bytes.append(byte)
            } else if byte == UInt8(ascii: "&") {
                raw("&amp;")
            } else if byte == UInt8(ascii: "'") {
                raw("&#x27;")
            } else {
                bytes.append(UInt8(ascii: "%"))
                bytes.append(Self.hexDigits[Int(byte >> 4)])
                bytes.append(Self.hexDigits[Int(byte & 0x0F)])
            }
        }
    }

    private static let newline = UInt8(ascii: "\n")
    private static let hexDigits = Array("0123456789ABCDEF".utf8)
    private static let hrefSafePunctuation = Set("-_.+!*(),%#@?=;:/$~".utf8)

    static func isHrefSafe(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
            UInt8(ascii: "0")...UInt8(ascii: "9"):
            true
        default:
            hrefSafePunctuation.contains(byte)
        }
    }
}

/// URL schemes cmark refuses to emit in its default (safe) mode: `javascript:`, `vbscript:`,
/// `file:`, and `data:` other than PNG/GIF/JPEG/WebP images. Matched case-insensitively.
enum DangerousURL {
    static func matches(_ url: String) -> Bool {
        let lowered = String(url.prefix(16)).lowercased()
        if safePrefixes.contains(where: lowered.hasPrefix) {
            return false
        }
        return dangerousPrefixes.contains(where: lowered.hasPrefix)
    }

    private static let safePrefixes = ["data:image/png", "data:image/gif", "data:image/jpeg", "data:image/webp"]
    private static let dangerousPrefixes = ["javascript:", "vbscript:", "file:", "data:"]
}
