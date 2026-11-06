import Foundation
import Testing

@testable import MdvCore

// Stress tests: hostile and huge inputs must render quickly, without crashing or overflowing the
// stack. Bounds are generous (debug builds on a loaded CI runner); the point is to catch
// quadratic blow-ups and crashes, not to benchmark.

/// Renders `markdown` with the default options (what the app and `mdv --html` use) and source
/// lines on, and returns the HTML and how long it took.
private func timedRender(_ markdown: String) -> (html: String, duration: Duration) {
    var options = RenderOptions()
    options.sourceLines = true
    let renderer = HTMLRenderer(options: options)
    var html = ""
    let duration = ContinuousClock().measure { html = renderer.render(markdown).html }
    return (html, duration)
}

/// The text of `html` with tags and whitespace removed.
private func textContent(_ html: String) -> String {
    html.replacing(/<[^>]*>/, with: "").filter { !$0.isWhitespace }
}

private func count(_ needle: String, in haystack: String) -> Int {
    haystack.ranges(of: needle).count
}

/// A case from cmark's `test/pathological_tests.py`: the input and a check on the output.
struct PathologicalCase: CustomTestStringConvertible, Sendable {
    let name: String
    let input: String
    let check: @Sendable (String) -> Bool

    var testDescription: String { name }

    static let all: [PathologicalCase] = [
        PathologicalCase(name: "nested strong emph", input: "*a **a " * 65_000 + "b" + " a** a*" * 65_000) {
            // Nesting past `MarkdownParser.maximumNestingDepth` is flattened, never lost.
            $0.contains("b") && count("<em>", in: $0) == count("</em>", in: $0) && count("<em>", in: $0) > 0
        },
        PathologicalCase(name: "many emph closers with no openers", input: "a_ " * 65_000) {
            count("a_", in: $0) == 65_000 && !$0.contains("<em>")
        },
        PathologicalCase(name: "many emph openers with no closers", input: "_a " * 65_000) {
            count("_a", in: $0) == 65_000 && !$0.contains("<em>")
        },
        PathologicalCase(name: "many link closers with no openers", input: "a]" * 65_000) {
            count("a]", in: $0) == 65_000
        },
        PathologicalCase(name: "many link openers with no closers", input: "[a" * 65_000) {
            count("[a", in: $0) == 65_000
        },
        PathologicalCase(name: "mismatched openers and closers", input: "*a_ " * 50_000) {
            count("*a_", in: $0) == 50_000
        },
        PathologicalCase(name: "openers and closers multiple of 3", input: "a**b" + "c* " * 50_000) {
            $0.hasPrefix("<p data-source-line=\"1\">a**b") && count("c*", in: $0) == 50_000
        },
        PathologicalCase(name: "link openers and emph closers", input: "[ a_" * 50_000) {
            count("[ a_", in: $0) == 50_000
        },
        PathologicalCase(name: "pattern [ (]( repeated", input: "[ (](" * 80_000) {
            count("[ (](", in: $0) == 80_000
        },
        PathologicalCase(name: "hard link/emph case", input: "**x [a*b**c*](d)") {
            $0.contains("**x <a href=\"d\">a<em>b**c</em></a>")
        },
        PathologicalCase(name: "nested brackets", input: "[" * 50_000 + "a" + "]" * 50_000) {
            $0.contains("[" * 50_000 + "a" + "]" * 50_000)
        },
        PathologicalCase(name: "nested block quotes", input: "> " * 50_000 + "a") {
            count("<blockquote", in: $0) == count("</blockquote>", in: $0)
                && count("<blockquote", in: $0) < MarkdownParser.maximumNestingDepth && textContent($0) == "a"
        },
        PathologicalCase(
            name: "deeply nested lists",
            input: (0..<1_000).map { String(repeating: "  ", count: $0) + "* a\n" }.joined()
        ) {
            count("<ul", in: $0) == count("</ul>", in: $0) && textContent($0) == "a" * 1_000
        },
        PathologicalCase(name: "U+0000 in input", input: "abc\u{0}de\u{0}") {
            $0 == "<p data-source-line=\"1\">abc\u{FFFD}de\u{FFFD}</p>\n"
        },
        PathologicalCase(name: "backticks", input: (1..<5_000).map { "e" + String(repeating: "`", count: $0) }.joined())
        {
            $0.hasPrefix("<p data-source-line=\"1\">e`") && $0.hasSuffix("</p>\n") && !$0.contains("<code>")
        },
        PathologicalCase(name: "unclosed links A", input: "[a](<b" * 30_000) {
            count("[a](&lt;b", in: $0) == 30_000
        },
        PathologicalCase(name: "unclosed links B", input: "[a](b" * 30_000) {
            count("[a](b", in: $0) == 30_000
        },
        PathologicalCase(name: "unclosed <!--", input: "</" + "<!--" * 300_000) {
            // The sanitizer drops the unterminated comment; nothing raw survives.
            !$0.contains("<!--")
        },
        PathologicalCase(
            name: "many references", input: (0..<50_000).map { "[\($0)]: /url\n" }.joined() + "[0] " * 1_000
        ) {
            count("<a href=\"/url\">0</a>", in: $0) == 1_000
        },
        PathologicalCase(
            name: "many table columns",
            input: "|" + "a|" * 10_000 + "\n|" + "-|" * 10_000 + "\n" + ("|" + "b|" * 10_000 + "\n") * 20
        ) {
            count("<th>", in: $0) == 10_000 && count("<td>", in: $0) == 200_000
        },
        PathologicalCase(name: "table with many rows", input: "|a|b|\n|-|-|\n" + "|1|2|\n" * 100_000) {
            count("<tr", in: $0) == 100_001
        },
        PathologicalCase(name: "nested inline links", input: "[" * 1_000 + "a" + "](b)" * 1_000) {
            count("<a href", in: $0) == 1
        },
        PathologicalCase(name: "many footnote references", input: "x[^a]" * 20_000 + "\n\n[^a]: note") {
            count("data-footnote-backref=\"\"", in: $0) == 20_000
        },
        PathologicalCase(name: "nested raw HTML", input: "<div>" * 50_000 + "a" + "</div>" * 50_000) {
            count("<div>", in: $0) == count("</div>", in: $0)
        },
        PathologicalCase(name: "many emoji shortcodes", input: ":tada: " * 100_000) {
            count("🎉", in: $0) == 100_000
        },
    ]
}

extension String {
    fileprivate static func * (string: String, count: Int) -> String {
        String(repeating: string, count: count)
    }
}

@Suite("Stress: pathological and large inputs")
struct StressTests {
    @Test("cmark's pathological cases render in linear-ish time", arguments: PathologicalCase.all)
    func pathological(_ testCase: PathologicalCase) {
        let (html, duration) = timedRender(testCase.input)
        #expect(testCase.check(html), "\(testCase.name): \(html.prefix(300))…")
        #expect(duration < .seconds(10), "\(testCase.name) took \(duration)")
    }

    @Test("an 8 MB document with every feature")
    func largeDocument() {
        let markdown = Self.largeDocument(bytes: 8 * 1024 * 1024)
        let (html, duration) = timedRender(markdown)
        #expect(duration < .seconds(20), "took \(duration)")
        #expect(html.utf8.count > markdown.utf8.count)
        // 4,000+ copies of each heading: every generated id is still unique. (Raw HTML ids are
        // the author's, namespaced with `user-content-`.)
        let ids = html.matches(of: /\sid="([^"]*)"/).map(\.1).filter { !$0.hasPrefix("user-content-") }
        #expect(Set(ids).count == ids.count)
        #expect(html.hasSuffix("</ol>\n</section>\n"))
    }

    @Test("a single 1 MB line")
    func longLine() {
        let line = String("word *emphasis* `code` [link](https://example.com) :tada: ~~gone~~ ".prefix(64))
        let markdown = String(repeating: line, count: 1024 * 1024 / line.utf8.count)
        #expect(markdown.utf8.count >= 1_000_000 && !markdown.contains("\n"))
        let (html, duration) = timedRender(markdown)
        #expect(duration < .seconds(5), "took \(duration)")
        #expect(html.hasPrefix("<p data-source-line=\"1\">word <em>emphasis</em>"))
        #expect(count("<code>code</code>", in: html) == markdown.utf8.count / line.utf8.count)
    }

    @Test("a single 1 MB line of code and of raw HTML")
    func longCodeAndHTMLLines() {
        let code = String(repeating: "let x = \"<y>\"; ", count: 1024 * 1024 / 15)
        let (codeHTML, codeDuration) = timedRender("```swift\n\(code)\n```")
        #expect(codeDuration < .seconds(5), "took \(codeDuration)")
        // Over the highlighting cap: plain escaped code.
        #expect(codeHTML.contains("let x = &quot;&lt;y&gt;&quot;;") && !codeHTML.contains("hljs"))

        let rawHTML = String(repeating: "<b onclick=\"x()\">bold</b><img src=\"javascript:x\"> ", count: 20_000)
        let (html, htmlDuration) = timedRender(rawHTML)
        #expect(htmlDuration < .seconds(5), "took \(htmlDuration)")
        #expect(count("<b>bold</b>", in: html) == 20_000)
        #expect(!html.contains("onclick") && !html.contains("javascript:"))
    }

    /// Varied Markdown exercising every node kind, extension, and mdv feature, repeated to `bytes`.
    static func largeDocument(bytes: Int) -> String {
        let chunk = """
            # Heading with *emphasis*, `code`, and :tada:

            A paragraph with **strong**, [a link](https://example.com "title"), ![image](a.png), an
            autolink <https://example.com>, www.example.com, ~~strike~~, &copy; entities,
            <span id="raw">inline html</span>, and a footnote[^note].\\
            Hard break above.

            ## Heading with *emphasis*, `code`, and :tada:

            > Quote with a list:
            > 1. one
            > 2. two

            - [x] task
            - [ ] task
              - nested
                1. deeper

            | a | b |
            |:--|--:|
            | 1 | 2[^note] |

            ```swift
            let x = "<code>"
            ```

                indented code

            <details><summary>raw block</summary>
            <p onclick="x()">kept, without the handler</p>
            </details>

            ***


            """
        let footnote = "\n[^note]: The note.\n"
        return String(repeating: chunk, count: bytes / chunk.utf8.count + 1) + footnote
    }
}
