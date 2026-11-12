import Foundation
import Testing

@testable import MdvCore

// Seeded fuzzing of the whole pipeline (frontmatter, parser, transforms, sanitizer, highlighter,
// renderer) with random Markdown mixed with raw HTML. Every failure message includes the seed and
// iteration, so it reproduces.
//
// The default run is short enough for `make test-core`. For a longer local run:
//
//     MDV_FUZZ_ITERATIONS=200000 MDV_FUZZ_SEED=$RANDOM swift test --filter RendererFuzzTests

/// Builds random Markdown documents from GFM building blocks, hostile raw HTML, and text chosen
/// to provoke id collisions (`# fn 1` beside footnote `[^1]`, repeated headings, ...).
private struct MarkdownFuzzer {
    var generator: SeededGenerator

    static let sentinel = "FUZZ-END"

    static let headingTexts = [
        "fn 1", "fnref 1", "fnref 1 2", "fn a", "fnref a 2", "fn a 2", "Footnote label", "footnote-label 1", "Title",
        "Title", "Title 1", ":tada: Party", "tada party", "Ünïcödé", "user content x", "", "*emph* `code`", "a  b",
        "fn %C3%BC", "fn-1-1",
    ]
    static let labels = ["1", "2", "a", "a-2", "a-2-1", "note", "ü", "%C3%BC", "fn", "1-1"]
    static let languages = [
        "swift", "js", "javascript", "python", "ruby", "html", "xml", "css", "json", "bash", "go", "rust", "c",
        "markdown", "diff", "nope", "\"><script>", "js{.x}", "",
    ]
    static let words = [
        "word", "text", "Ünïcödé", "日本語", "עברית", "🎉", "👩‍👩‍👧", "e\u{301}", "\u{0}", "&amp;", "&copy;", "&#0;",
        "&#x110000;", "&bogus;", "\\*", "\\", "<", ">", "\"", "'", "`", "*", "_", "~", "[", "]", "(", ")", "!", "|",
        "#", ":tada:", ":+1:", ":nope:", "www.example.com", "https://example.com", "a@b.co", "  ", "\t",
    ]
    static let urls = [
        "https://example.com", "/relative", "#frag", "javascript:alert(1)", "JAVASCRIPT:x", "vbscript:x", "file:///etc",
        "data:text/html,x", "mailto:a@b.co", "x \"title\"", "<a b>", "",
    ]
    static let rawHTML = [
        "<b>bold</b>", "<span id=\"x\">s</span>", "<a name=\"n\" href=\"javascript:x\">a</a>", "<img src=x onerror=y>",
        "<script>alert(1)</script>", "<SCRIPT>", "</div>", "<div>", "<details><summary>s</summary>", "</details>",
        "<!-- comment -->", "<!--", "<iframe src=x>", "<style>*{}</style>", "<sup>1</sup>", "<input type=checkbox>",
        "<section id=\"fn-1\">", "<h2 id=\"footnote-label\">", "<svg onload=x>", "<p style=\"x\" onclick=\"y\">",
    ]

    init(seed: UInt64) {
        generator = SeededGenerator(state: seed)
    }

    mutating func document() -> String {
        var lines: [String] = []
        if chance(8) {
            lines += pick([["---", "title: Fuzz", "tags: [a, b]", "---"], ["+++", "title = 'Fuzz'", "+++"], ["---"]])
        }
        for _ in 0..<int(1...10) {
            lines += block(depth: 0) + [""]
        }
        for label in Self.labels where chance(3) {
            lines += ["[^\(label)]: " + inline(), ""]
        }
        let newline = chance(10) ? "\r\n" : "\n"
        // The closer ends anything left open at the top level, so the sentinel paragraph after it
        // must be rendered. (An unclosed `<svg>` or `<script>` hides every later sibling block in
        // its container until a closing tag in a raw HTML block; GitHub keeps them.)
        return (lines + ["", Self.closer(repeating: 40), "", Self.sentinel, ""]).joined(separator: newline)
    }

    /// Whether `markdown` parses to body blocks ending with the closer and then the sentinel
    /// paragraph. Not always: an unclosed top-level code fence (`~~~` can come out of inline
    /// text) or HTML block swallows them, and then the sentinel may rightly be dropped.
    static func endsWithSentinel(_ markdown: String) -> Bool {
        let body = MarkdownParser(extensions: MarkdownExtension.gfm).parse(markdown).children.filter {
            !$0.kind.isFootnoteDefinition
        }
        guard body.count >= 2, case .htmlBlock(let closer) = body[body.count - 2].kind,
            closer.hasPrefix("</div> -->"), body[body.count - 1].children.first?.kind == .text(sentinel)
        else {
            return false
        }
        return true
    }

    /// One raw HTML line that ends every HTML block type and closes `count` levels of each
    /// element the sanitizer drops with its content. The leading `</div>` makes the line an HTML
    /// block of its own (type 6) rather than inline HTML in a paragraph, which is a separate
    /// container that can't close elements opened outside it.
    static func closer(repeating count: Int) -> String {
        let tags = HTMLSanitizerPolicy.rawTextElements.union(HTMLSanitizerPolicy.contentDroppingElements).sorted()
        return "</div> --> ?> ]]>" + String(repeating: tags.map { "</\($0)>" }.joined(), count: count)
    }

    private mutating func block(depth: Int) -> [String] {
        let canNest = depth < 4
        switch int(0...12) {
        case 0:
            return [String(repeating: "#", count: int(1...6)) + " " + pick(Self.headingTexts) + optionalInline()]
        case 1:
            return [pick(Self.headingTexts), pick(["===", "---"])]
        case 2 where canNest:
            return nested(prefix: "> ", continuation: "> ", depth: depth)
        case 3 where canNest:
            let marker = pick(["- ", "* ", "1. ", "2) ", "- [ ] ", "- [x] ", "* [X] "])
            return nested(prefix: marker, continuation: String(repeating: " ", count: marker.count), depth: depth)
        case 4:
            let fence = pick(["```", "~~~", "````"])
            let body = (0..<int(0...4)).map { _ in pick(["let x = \"<y>\" // é", "func f() {}", "<script>", "\t}"]) }
            // Sometimes unclosed inside a container, where it runs to the container's end. (At the
            // top level it would swallow the closer and sentinel.)
            return [fence + pick(Self.languages)] + body + (depth > 0 && chance(4) ? [] : [fence])
        case 5:
            let columns = int(1...4)
            let row = { (cell: () -> String) in "| " + (0..<columns).map { _ in cell() }.joined(separator: " | ") + " |"
            }
            var table = [row { pick(Self.words) }, row { pick(["---", ":--", "--:", ":-:"]) }]
            for _ in 0..<int(0...3) {
                table.append(row { inline() })
            }
            return table
        case 6:
            // Raw HTML block. The closer line ends every HTML block type, so nothing after it is
            // swallowed.
            return (0..<int(1...3)).map { _ in pick(Self.rawHTML) } + [Self.closer(repeating: 3)]
        case 7:
            return [pick(["***", "---", "___", "* * *"])]
        case 8:
            return ["    indented code \(pick(Self.words))"]
        case 9:
            return ["[^\(pick(Self.labels))]: " + inline()]
        default:
            return (0..<int(1...3)).map { _ in inline() + pick(["", "  ", "\\"]) }
        }
    }

    private mutating func nested(prefix: String, continuation: String, depth: Int) -> [String] {
        var inner: [String] = []
        for index in 0..<int(1...3) {
            if index > 0 {
                inner.append("")
            }
            inner += block(depth: depth + 1)
        }
        return inner.enumerated().map { index, line in
            (index == 0 ? prefix : continuation) + line
        }
    }

    private mutating func inline() -> String {
        var text = ""
        for _ in 0..<int(1...8) {
            switch int(0...12) {
            case 0: text += "*" + pick(Self.words) + "*"
            case 1: text += "**" + pick(Self.words) + " _" + pick(Self.words) + "_**"
            case 2: text += "`" + pick(Self.words) + "`"
            case 3: text += "[" + pick(Self.words) + "](" + pick(Self.urls) + ")"
            case 4: text += "![" + pick(Self.words) + "](" + pick(Self.urls) + ")"
            case 5: text += "<" + pick(Self.urls) + ">"
            case 6: text += "[^" + pick(Self.labels) + "]"
            case 7: text += pick(Self.rawHTML)
            case 8: text += "~~" + pick(Self.words) + "~~"
            default: text += pick(Self.words)
            }
            text += pick([" ", "", " "])
        }
        return text
    }

    private mutating func optionalInline() -> String {
        chance(4) ? " " + inline() : ""
    }

    private mutating func int(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &generator)
    }

    private mutating func chance(_ oneIn: Int) -> Bool {
        int(1...oneIn) == 1
    }

    private mutating func pick<T>(_ items: [T]) -> T {
        items[int(0...(items.count - 1))]
    }
}

/// Invariants every rendering must satisfy; returns the violated ones.
private func violations(in html: String, input: String, expectsSentinel: Bool) -> [String] {
    var problems = OutputChecker.problems(in: html, isMarkdown: true, extraElements: ["section", "input"])

    // Every element id mdv generates (headings, footnotes) is unique. Raw HTML ids belong to the
    // author and are namespaced by the sanitizer.
    let ids = html.matches(of: /\sid="([^"]*)"/.matchingSemantics(.unicodeScalar)).map { String($0.1) }
    let generated = ids.filter { !$0.hasPrefix("user-content-") }
    if Set(generated).count != generated.count {
        let duplicates = Dictionary(grouping: generated) { $0 }.filter { $0.value.count > 1 }.keys
        problems.append("duplicate ids \(duplicates.sorted())")
    }
    // Generated in-page links resolve: heading anchors, footnote references and back-links.
    let idSet = Set(ids)
    let targets =
        html.matches(of: /aria-hidden="true" href="#([^"]*)"/.matchingSemantics(.unicodeScalar)).map(\.1)
        // Footnote back-links (`#fnref-…`) can dangle, as on GitHub: cmark counts references
        // that aren't rendered (inside an unreferenced note, or raw HTML the sanitizer drops).
        + html.matches(of: /href="#(fn-[^"]*)"/).map(\.1)
        + html.matches(of: /aria-describedby="([^"]*)"/).map(\.1)
    for target in targets where !idSet.contains(String(target)) {
        problems.append("dangling reference to \(target)")
    }
    // Valid, complete UTF-8: nothing truncated, no replacement characters the input didn't ask for.
    if expectsSentinel, !html.contains(MarkdownFuzzer.sentinel) {
        problems.append("output truncated (no sentinel)")
    }
    if html.contains("\u{FFFD}"), !input.contains("\u{0}"), !input.contains("&#0;"), !input.contains("&#x110000;") {
        problems.append("unexpected U+FFFD")
    }
    // Source lines never decrease before the footnotes section (definitions move to the end).
    let body = html.components(separatedBy: "<section data-footnotes").first ?? html
    let lines = body.matches(of: /data-source-line="(\d+)"/).compactMap { Int($0.1) }
    if zip(lines, lines.dropFirst()).contains(where: { $0 > $1 }) {
        problems.append("data-source-line decreases: \(lines)")
    }
    return problems
}

@Suite("Renderer: fuzz")
struct RendererFuzzTests {
    static let environment = ProcessInfo.processInfo.environment
    static let iterations = environment["MDV_FUZZ_ITERATIONS"].flatMap(Int.init) ?? 3_000
    static let seed = environment["MDV_FUZZ_SEED"].flatMap(UInt64.init) ?? 0x6D64_7631_32

    @Test("random Markdown and HTML: safe, unique ids, complete UTF-8, deterministic")
    func randomDocuments() {
        var fuzzer = MarkdownFuzzer(seed: Self.seed)
        var options = RenderOptions()
        options.sourceLines = true
        let renderer = HTMLRenderer(options: options)
        var tableOptions = options
        tableOptions.frontmatterDisplay = .table
        let tableRenderer = HTMLRenderer(options: tableOptions)

        var sentinelChecks = 0
        for iteration in 0..<Self.iterations {
            let input = fuzzer.document()
            let html = (iteration % 4 == 0 ? tableRenderer : renderer).render(input).html
            let expectsSentinel = MarkdownFuzzer.endsWithSentinel(input)
            sentinelChecks += expectsSentinel ? 1 : 0
            let problems = violations(in: html, input: input, expectsSentinel: expectsSentinel)
            #expect(
                problems.isEmpty,
                "seed \(Self.seed) #\(iteration): \(problems)\n--- input\n\(input.debugDescription)\n--- html\n\(html)")
            if !problems.isEmpty {
                break
            }
            if iteration % 16 == 0 {
                #expect(renderer.render(input).html == renderer.render(input).html, "nondeterministic #\(iteration)")
            }
        }
        // The truncation check must not be vacuous.
        #expect(sentinelChecks > Self.iterations * 3 / 4, "\(sentinelChecks) of \(Self.iterations)")
    }
}
