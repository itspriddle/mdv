import Testing

@Suite("Spec harness")
struct SpecHarnessTests {
    /// The doctests from cmark's `test/normalize.py`.
    @Test(
        "normalizes like normalize.py",
        arguments: [
            ("<p>a  \t b</p>", "<p>a b</p>"),
            ("<p>a  \t\nb</p>", "<p>a b</p>"),
            (" <p>a  b</p>", "<p>a b</p>"),
            ("<p>a  b</p> ", "<p>a b</p>"),
            ("\n\t<p>\n\t\ta  b\t\t</p>\n\t", "<p>a b</p>"),
            ("<i>a  b</i> ", "<i>a b</i> "),
            ("<br />", "<br>"),
            ("<a title=\"bar\" HREF=\"foo\">x</a>", "<a href=\"foo\" title=\"bar\">x</a>"),
            ("&#8704;&amp;&gt;&lt;&quot;", "\u{2200}&amp;&gt;&lt;&quot;"),
        ])
    func normalize(input: String, expected: String) {
        #expect(HTMLNormalizer.normalize(input) == expected)
    }

    @Test("keeps whitespace in pre, comments, and unknown entities")
    func preserves() {
        #expect(HTMLNormalizer.normalize("<pre><code>a  \n b</code></pre>") == "<pre><code>a  \n b</code></pre>")
        #expect(HTMLNormalizer.normalize("<!-- a  b -->") == "<!-- a  b -->")
        #expect(HTMLNormalizer.normalize("<p>&copy; &#x41;</p>") == "<p>&copy; A</p>")
    }

    @Test("parses examples: numbering, sections, tags, tabs, and CRs")
    func parse() throws {
        let fence = String(repeating: "`", count: 32)
        let text = """
            # Section A

            \(fence) example
            a→b\r
            .
            <p>a→b</p>
            \(fence)

            ## Section B

            \(fence) example disabled
            x
            .
            y
            \(fence)

            \(fence) example table footnotes
            | a |
            .
            <table>
            \(fence)

            """
        let examples = try SpecParser.parse(text, file: "test.txt")
        #expect(examples.map(\.number) == [1, 2, 3])
        #expect(examples.map(\.section) == ["Section A", "Section B", "Section B"])
        #expect(examples[0].markdown == "a\tb\r\n")
        #expect(examples[0].html == "<p>a\tb</p>\n")
        #expect(examples[1].isDisabled)
        #expect(examples[2].tags == ["table", "footnotes"])
        #expect(examples[2].testDescription == "test.txt #3 (Section B)")
    }

    @Test("rejects an unterminated example")
    func unterminated() {
        let text = String(repeating: "`", count: 32) + " example\nfoo\n"
        #expect(throws: SpecFileError.self) {
            try SpecParser.parse(text, file: "bad.txt")
        }
    }
}
