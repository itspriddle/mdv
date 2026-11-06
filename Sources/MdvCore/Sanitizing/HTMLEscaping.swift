/// Escaping and character-reference handling for re-serializing sanitized raw HTML.
enum HTMLEscaping {
    /// Escapes raw-HTML character data for element content.
    ///
    /// `<` and `>` are always escaped, so the browser can't see a tag the sanitizer didn't
    /// emit. A `&` that may start a character reference (`&name`, `&#…`) is kept, so entities
    /// in raw HTML render as written; a character reference in element content only ever
    /// produces text. Any other `&` is escaped.
    static func appendText(_ text: String, to output: inout String) {
        let scalars = Array(text.unicodeScalars)
        var escaped = String.UnicodeScalarView()
        for (index, scalar) in scalars.enumerated() {
            switch scalar {
            case "<":
                escaped.append(contentsOf: "&lt;".unicodeScalars)
            case ">":
                escaped.append(contentsOf: "&gt;".unicodeScalars)
            case "&":
                let next = index + 1 < scalars.count ? scalars[index + 1] : nil
                if let next, next == "#" || isASCIIAlphanumeric(next) {
                    escaped.append(scalar)
                } else {
                    escaped.append(contentsOf: "&amp;".unicodeScalars)
                }
            case "\u{0}":
                escaped.append("\u{FFFD}")
            default:
                escaped.append(scalar)
            }
        }
        output.append(String(escaped))
    }

    static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
    }
}

/// A raw attribute value, decoded for policy checks and re-escaped for output.
///
/// Every character reference that a browser could turn into an ASCII character (all numeric
/// references and the ASCII-valued named references) is decoded here, so `decoded` sees
/// what the browser would see in every position that matters for URL schemes. Other named
/// references (`&eacute;`, `&nbsp;`, …) can only produce non-ASCII characters, which can't
/// form a URL scheme; they are left in `decoded` as written and kept verbatim in `serialized`
/// so they still render.
struct AttributeValue {
    /// The value as the policy should judge it.
    private(set) var decoded = ""
    /// The value escaped for a double-quoted attribute.
    private(set) var serialized = ""

    init(_ raw: String) {
        let scalars = Array(raw.unicodeScalars)
        var decoded = String.UnicodeScalarView()
        var serialized = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            guard scalar == "&" else {
                Self.append(scalar, decoded: &decoded, serialized: &serialized)
                index += 1
                continue
            }
            if let (value, end) = Self.numericReference(in: scalars, at: index) {
                decoded.append(value)
                if (0x20...0x7E).contains(value.value) {
                    Self.appendEscaped(value, to: &serialized)
                } else {
                    // Re-emit non-printable and non-ASCII values as references, so the
                    // browser applies its own mapping (e.g. `&#x80;` is €).
                    serialized.append(
                        contentsOf: "&#x\(String(value.value, radix: 16, uppercase: true));".unicodeScalars)
                }
                index = end
                continue
            }
            var nameEnd = index + 1
            while nameEnd < scalars.count, HTMLEscaping.isASCIIAlphanumeric(scalars[nameEnd]) {
                nameEnd += 1
            }
            let name = String(String.UnicodeScalarView(scalars[(index + 1)..<nameEnd]))
            let hasSemicolon = nameEnd < scalars.count && scalars[nameEnd] == ";"
            if hasSemicolon, let value = HTMLEntities.asciiValued[name] {
                for character in value.unicodeScalars {
                    Self.append(character, decoded: &decoded, serialized: &serialized)
                }
                index = nameEnd + 1
            } else if !hasSemicolon, let value = HTMLEntities.legacyASCIIValued[name],
                nameEnd >= scalars.count || scalars[nameEnd] != "="
            {
                // Legacy references without `;` are decoded in attributes unless followed by
                // an alphanumeric (impossible here: the name run is maximal) or `=`.
                Self.append(value, decoded: &decoded, serialized: &serialized)
                index = nameEnd
            } else if !name.isEmpty {
                // Not ASCII-valued: keep the reference as written.
                let reference = "&" + name
                decoded.append(contentsOf: reference.unicodeScalars)
                serialized.append(contentsOf: reference.unicodeScalars)
                index = nameEnd
            } else {
                Self.append(scalar, decoded: &decoded, serialized: &serialized)
                index += 1
            }
        }
        self.decoded = String(decoded)
        self.serialized = String(serialized)
    }

    private static func append(
        _ scalar: Unicode.Scalar, decoded: inout String.UnicodeScalarView, serialized: inout String.UnicodeScalarView
    ) {
        let scalar = scalar == "\u{0}" ? "\u{FFFD}" : scalar
        decoded.append(scalar)
        appendEscaped(scalar, to: &serialized)
    }

    private static func appendEscaped(_ scalar: Unicode.Scalar, to serialized: inout String.UnicodeScalarView) {
        switch scalar {
        case "&": serialized.append(contentsOf: "&amp;".unicodeScalars)
        case "\"": serialized.append(contentsOf: "&quot;".unicodeScalars)
        case "<": serialized.append(contentsOf: "&lt;".unicodeScalars)
        case ">": serialized.append(contentsOf: "&gt;".unicodeScalars)
        default: serialized.append(scalar)
        }
    }

    /// Parses `&#123;`, `&#x7B;` (the `;` is optional) at `start`. Returns the value as a
    /// browser maps it (invalid code points become U+FFFD) and the index after the reference.
    private static func numericReference(in scalars: [Unicode.Scalar], at start: Int) -> (Unicode.Scalar, Int)? {
        var index = start + 1
        guard index < scalars.count, scalars[index] == "#" else {
            return nil
        }
        index += 1
        var radix: UInt32 = 10
        if index < scalars.count, scalars[index] == "x" || scalars[index] == "X" {
            radix = 16
            index += 1
        }
        let digitsStart = index
        var value: UInt32 = 0
        while index < scalars.count, let digit = asciiDigitValue(scalars[index]), digit < radix {
            // Clamp so huge values can't overflow; anything past U+10FFFF is invalid anyway.
            value = min(value * radix + digit, 0x11_0000)
            index += 1
        }
        guard index > digitsStart else {
            return nil
        }
        if index < scalars.count, scalars[index] == ";" {
            index += 1
        }
        let replacement: Unicode.Scalar = "\u{FFFD}"
        let scalar: Unicode.Scalar =
            switch value {
            case 0, 0xD800...0xDFFF, 0x11_0000...: replacement
            default: Unicode.Scalar(value) ?? replacement
            }
        return (scalar, index)
    }

    /// The value of an ASCII hex digit. (`Character.hexDigitValue` also accepts fullwidth
    /// forms, which browsers don't.)
    private static func asciiDigitValue(_ scalar: Unicode.Scalar) -> UInt32? {
        switch scalar {
        case "0"..."9": scalar.value - 0x30
        case "a"..."f": scalar.value - 0x61 + 10
        case "A"..."F": scalar.value - 0x41 + 10
        default: nil
        }
    }
}
