import Testing

@testable import MdvCore

// MARK: - Fuzz

/// Deterministic SplitMix64, so failures reproduce.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

private enum Soup {
    static let tags = [
        "script", "SCRIPT", "scr\u{0}ipt", "svg", "img", "a", "div", "p", "details", "summary", "iframe", "style",
        "table", "td", "li", "b", "span", "textarea", "title", "xmp", "math", "template", "noscript", "source",
        "object", "foo", "br",
    ]
    static let attributes = [
        "href", "src", "onerror", "ONLOAD", "onclick", "style", "id", "name", "alt", "title", "srcset", "cite",
        "longdesc", "on", "open", "xlink:href", "/onerror", "\"onerror", "align",
    ]
    static let values = [
        "javascript:alert(1)", "JaVaScRiPt:alert(1)", "jav&#x09;ascript:alert(1)", "&#106;avascript:x",
        "javascript&colon;x", "java\u{0}script:x", " \u{1}javascript:x", "vbscript:x", "data:text/html,x",
        "https://e.com", "x.png", "#frag", "mailto:a@b", "x onerror=alert(1)", "\"><script>alert(1)</script>",
        "&#x6A&#x61&#x76&#x61&#x73&#x63&#x72&#x69&#x70&#x74&#x3A;x", "x.png 1x, javascript:y 2x", "",
    ]
    static let noise = [
        "<", ">", "/", "\"", "'", "=", " ", "\t", "\n", "\u{0}", "<!--", "-->", "--!>", "</", "<!", "<?", "&#", "&",
        "&lt;", "`", "text", "*em*", "\n\n", "> ", "- ", "    ",
    ]

    static func make(using generator: inout SeededGenerator) -> String {
        var html = ""
        for _ in 0..<Int.random(in: 1...12, using: &generator) {
            switch Int.random(in: 0..<10, using: &generator) {
            case 0...3:
                html += "<" + pick(tags, &generator)
                for _ in 0..<Int.random(in: 0...3, using: &generator) {
                    html += pick([" ", "/", "\t", "\n", ""], &generator) + pick(attributes, &generator)
                    let value = pick(values, &generator)
                    html += pick(["=\"\(value)\"", "='\(value)'", "=\(value)", ""], &generator)
                }
                html += pick([">", "/>", " >", ""], &generator)
            case 4...5:
                html += "</" + pick(tags, &generator) + pick([">", " x>", ""], &generator)
            default:
                html += pick(noise, &generator)
            }
        }
        return html
    }

    private static func pick(_ items: [String], _ generator: inout SeededGenerator) -> String {
        items[Int.random(in: 0..<items.count, using: &generator)]
    }
}

@Suite("HTMLSanitizer: fuzz")
struct HTMLSanitizerFuzzTests {
    @Test("random tag and attribute soup never yields script, handlers, or bad URLs")
    func tagSoup() {
        var generator = SeededGenerator(state: 0x6D64_7637)
        for iteration in 0..<10_000 {
            let input = Soup.make(using: &generator)
            let fragment = sanitized(input)
            let markdown = rendered(input)
            #expect(
                OutputChecker.problems(in: fragment).isEmpty, "#\(iteration) \(input.debugDescription) → \(fragment)")
            #expect(
                OutputChecker.problems(in: markdown, isMarkdown: true).isEmpty,
                "#\(iteration) \(input.debugDescription) → \(markdown)")
            // Sanitized output is a fixed point.
            #expect(sanitized(fragment) == fragment, "#\(iteration) \(input.debugDescription)")
        }
    }
}
