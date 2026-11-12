/// URL scheme checks for sanitized attributes.
enum URLSchemePolicy {
    /// Whether `url` (with character references already decoded) is relative or uses one of
    /// `schemes`.
    ///
    /// Stricter than a URL parser on purpose, like the `sanitize` gem: every character up to
    /// U+0020 and DEL is removed first (browsers strip tab and newlines anywhere and leading
    /// controls), and then anything before a `:` that comes before the first `/`, `?`, or `#`
    /// is the scheme and must be allowlisted. So `jav&#x09;ascript:`, ` javascript:`, and even
    /// `foo bar:x` are rejected, and `/a:b`, `?a:b`, and `#a:b` are relative.
    static func allows(_ url: String, schemes: Set<String>) -> Bool {
        var scheme = ""
        for scalar in url.unicodeScalars where scalar.value > 0x20 && scalar.value != 0x7F {
            switch scalar {
            case ":":
                return schemes.contains(scheme.lowercased())
            case "/", "?", "#":
                return true
            default:
                scheme.unicodeScalars.append(scalar)
            }
        }
        return true
    }

    /// Every comma- or whitespace-separated piece of a `srcset`, so each URL is checked
    /// whatever the descriptors are. Over-splitting only makes the check stricter.
    static func srcsetURLs(_ srcset: String) -> [String] {
        srcset.split { $0 == "," || $0.isWhitespace }.map(String.init)
    }
}
