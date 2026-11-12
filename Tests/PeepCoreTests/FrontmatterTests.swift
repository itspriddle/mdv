import Foundation
import Testing

@testable import MdvCore

/// Start lines of every heading, in document order.
private func headingLines(_ root: MarkdownNode) -> [Int?] {
    var lines: [Int?] = []
    var stack = [root]
    while let node = stack.popLast() {
        if case .heading = node.kind {
            lines.append(node.sourceRange?.start.line)
        }
        stack.append(contentsOf: node.children.reversed())
    }
    return lines
}

@Suite("Frontmatter detection")
struct FrontmatterDetectionTests {
    @Test("detects YAML and splits off the body")
    func yaml() throws {
        let extracted = try #require(Frontmatter.extract(from: "---\ntitle: Hello\ntags: [a, b]\n---\n# Body\n"))
        #expect(extracted.frontmatter.format == .yaml)
        #expect(extracted.frontmatter.raw == "title: Hello\ntags: [a, b]\n")
        #expect(extracted.frontmatter.lineCount == 4)
        #expect(extracted.frontmatter.error == nil)
        #expect(
            extracted.frontmatter.entries == [
                FrontmatterEntry(key: "title", value: .scalar("Hello")),
                FrontmatterEntry(key: "tags", value: .array([.scalar("a"), .scalar("b")])),
            ]
        )
        #expect(extracted.frontmatter.title == "Hello")
        #expect(extracted.body == "# Body\n")
    }

    @Test("detects TOML without parsing it")
    func toml() throws {
        let extracted = try #require(Frontmatter.extract(from: "+++\ntitle = \"Hi\"\n+++\ntext"))
        #expect(extracted.frontmatter.format == .toml)
        #expect(extracted.frontmatter.raw == "title = \"Hi\"\n")
        #expect(extracted.frontmatter.entries == nil)
        #expect(extracted.frontmatter.values == nil)
        #expect(extracted.frontmatter.error == nil)
        #expect(extracted.frontmatter.title == nil)
        #expect(extracted.body == "text")
    }

    @Test("allows a leading byte order mark")
    func byteOrderMark() throws {
        let extracted = try #require(Frontmatter.extract(from: "\u{FEFF}---\na: 1\n---\nbody"))
        #expect(extracted.frontmatter.values == ["a": .scalar("1")])
        #expect(extracted.body == "body")
    }

    @Test("closes YAML with ...")
    func documentEndMarker() throws {
        let extracted = try #require(Frontmatter.extract(from: "---\na: 1\n...\nbody"))
        #expect(extracted.frontmatter.values == ["a": .scalar("1")])
        #expect(extracted.body == "body")
        #expect(Frontmatter.extract(from: "+++\na = 1\n...\nbody") == nil)
    }

    @Test("an empty block is frontmatter with no values")
    func empty() throws {
        let extracted = try #require(Frontmatter.extract(from: "---\n---\n# Title\n"))
        #expect(extracted.frontmatter.raw.isEmpty)
        #expect(extracted.frontmatter.entries == [])
        #expect(extracted.frontmatter.error == nil)
        #expect(extracted.frontmatter.lineCount == 2)
        #expect(extracted.body == "# Title\n")

        let comments = try #require(Frontmatter.extract(from: "---\n# just a comment\n\n---\n"))
        #expect(comments.frontmatter.entries == [])
    }

    @Test("an unclosed block is ordinary Markdown")
    func unclosed() {
        #expect(Frontmatter.extract(from: "---\ntitle: x\n\nbody\n") == nil)
        #expect(Frontmatter.extract(from: "---") == nil)
        #expect(Frontmatter.extract(from: "---\n") == nil)
        let html = HTMLRenderer().render("---\ntitle: x\n").html
        #expect(html == "<hr />\n<p>title: x</p>\n")
    }

    @Test("--- after line 1 is not frontmatter")
    func notAtStart() {
        #expect(Frontmatter.extract(from: "\n---\na: 1\n---\n") == nil)
        #expect(Frontmatter.extract(from: " ---\na: 1\n---\n") == nil)
        #expect(Frontmatter.extract(from: "# Title\n---\na: 1\n---\n") == nil)
        let rendered = HTMLRenderer().render("Title\n---\n\ntext\n\n---\n")
        #expect(rendered.frontmatter == nil)
        #expect(
            rendered.html
                == anchoredHeading(2, "title", "Title") + "\n<p>text</p>\n<hr />\n"
        )
    }

    @Test("fences must stand alone on their lines")
    func fenceShape() throws {
        #expect(Frontmatter.extract(from: "----\na: 1\n----\n") == nil)
        #expect(Frontmatter.extract(from: "--- a\nb: 1\n---\n") == nil)
        #expect(Frontmatter.extract(from: "---\na: 1\n--- x\n") == nil)
        let trailing = try #require(Frontmatter.extract(from: "--- \t\na: 1\n---  \nbody"))
        #expect(trailing.body == "body")
        let atEnd = try #require(Frontmatter.extract(from: "---\na: 1\n---"))
        #expect(atEnd.body.isEmpty)
        #expect(atEnd.frontmatter.lineCount == 3)
    }

    @Test("handles CRLF and CR line endings", arguments: ["\r\n", "\r"])
    func lineEndings(newline: String) throws {
        let source = ["---", "title: T", "---", "", "# H"].joined(separator: newline)
        let extracted = try #require(Frontmatter.extract(from: source))
        #expect(extracted.frontmatter.title == "T")
        #expect(extracted.frontmatter.lineCount == 3)
        #expect(extracted.body == "\(newline)# H")
        let tree = MarkdownParser().parse(String(extracted.body), lineOffset: extracted.frontmatter.lineCount)
        #expect(headingLines(tree) == [5])
    }
}

@Suite("YAML frontmatter parsing")
struct YAMLFrontmatterTests {
    @Test("keeps key order, scalar text, nulls, and nesting")
    func values() throws {
        let yaml = """
            version: 1.10
            draft: false
            empty:
            tilde: ~
            quoted: "a \\"b\\""
            author:
              name: Ada
              links: [x, y]
            """
        let frontmatter = YAMLFrontmatter.parse(yaml, lineCount: 0)
        #expect(frontmatter.error == nil)
        #expect(
            frontmatter.entries == [
                FrontmatterEntry(key: "version", value: .scalar("1.10")),
                FrontmatterEntry(key: "draft", value: .scalar("false")),
                FrontmatterEntry(key: "empty", value: .null),
                FrontmatterEntry(key: "tilde", value: .null),
                FrontmatterEntry(key: "quoted", value: .scalar("a \"b\"")),
                FrontmatterEntry(
                    key: "author",
                    value: .table([
                        FrontmatterEntry(key: "name", value: .scalar("Ada")),
                        FrontmatterEntry(key: "links", value: .array([.scalar("x"), .scalar("y")])),
                    ])
                ),
            ]
        )
    }

    @Test("malformed YAML is hidden and reports an error")
    func malformed() throws {
        let markdown = "---\ntitle: [unclosed\n---\n# Body\n"
        let rendered = HTMLRenderer().render(markdown)
        let frontmatter = try #require(rendered.frontmatter)
        #expect(frontmatter.entries == nil)
        #expect(frontmatter.error?.hasPrefix("Invalid YAML frontmatter") == true)
        #expect(
            rendered.html == anchoredHeading(1, "body", "Body") + "\n")
        #expect(rendered.title == "Body")

        var options = RenderOptions()
        options.frontmatterDisplay = .table
        #expect(
            HTMLRenderer(options: options).render(markdown).html
                == anchoredHeading(1, "body", "Body") + "\n")
    }

    @Test("YAML that is not a mapping reports an error")
    func notMapping() {
        #expect(YAMLFrontmatter.parse("just text", lineCount: 0).error != nil)
        #expect(YAMLFrontmatter.parse("- a\n- b", lineCount: 0).error != nil)
        #expect(YAMLFrontmatter.parse("[a]: 1", lineCount: 0).error != nil)
    }

    @Test("oversized YAML is hidden and not parsed")
    func oversized() throws {
        let value = String(repeating: "x", count: YAMLFrontmatter.maximumSize)
        let rendered = HTMLRenderer().render("---\ntitle: \(value)\n---\ntext\n")
        let frontmatter = try #require(rendered.frontmatter)
        #expect(frontmatter.entries == nil)
        #expect(frontmatter.error?.contains("larger than 64 KB") == true)
        #expect(rendered.html == "<p>text</p>\n")
    }

    @Test("allows a few aliases")
    func someAliases() {
        let frontmatter = YAMLFrontmatter.parse("base: &b {a: 1}\none: *b\ntwo: *b\n", lineCount: 0)
        #expect(frontmatter.error == nil)
        #expect(frontmatter.values?["two"] == .table([FrontmatterEntry(key: "a", value: .scalar("1"))]))
    }

    @Test("refuses alias bombs before Yams expands them")
    func aliasBomb() {
        var yaml = "a: &a [x, x, x, x, x, x, x, x, x, x]\n"
        var previous = "a"
        for name in ["b", "c", "d", "e", "f", "g", "h", "i"] {
            let aliases = Array(repeating: "*\(previous)", count: 10).joined(separator: ", ")
            yaml += "\(name): &\(name) [\(aliases)]\n"
            previous = name
        }
        yaml += "? *i\n: boom\n"
        let frontmatter = YAMLFrontmatter.parse(yaml, lineCount: 0)
        #expect(frontmatter.entries == nil)
        #expect(frontmatter.error?.contains("aliases") == true)
    }

    @Test("limits values after alias expansion")
    func expansionLimit() {
        let items = Array(repeating: "x", count: 2_000).joined(separator: ", ")
        let yaml = "a: &a [\(items)]\nb: [*a, *a, *a, *a, *a, *a]\n"
        let frontmatter = YAMLFrontmatter.parse(yaml, lineCount: 0)
        #expect(frontmatter.entries == nil)
        #expect(frontmatter.error?.contains("too large") == true)
    }

    @Test("deep nesting fails cleanly on a small-stack thread")
    func deepNesting() async {
        let limited = String(repeating: "[", count: 999) + String(repeating: "]", count: 999)
        let beyondLibyaml = String(repeating: "- ", count: 5_000) + "x"
        for nested in [limited, beyondLibyaml] {
            let frontmatter = await Task.detached { YAMLFrontmatter.parse("a: \(nested)", lineCount: 0) }.value
            #expect(frontmatter.entries == nil)
            #expect(frontmatter.error != nil)
        }
    }

    @Test(
        "the alias pre-scan counts aliases only where a node starts",
        arguments: [
            ("a: *x", 1),
            ("- *x\n- [*y, {k: *z}]", 3),
            ("*x : value", 1),
            ("? *x\n: v", 1),
            ("a: !!str *x", 1),
            ("a: &anchor *x", 1),
            ("a: some *emphasis* here", 0),
            ("a: \"*quoted\"", 0),
            ("a: '*it''s*'", 0),
            ("a: \"multi\n  *line\"", 0),
            ("a: # *comment", 0),
            ("a: |\n  * item\n  * item\nb: *x", 1),
            ("- >-\n    *folded\n\n    *more\n- *x", 1),
            ("a: x*y", 0),
        ]
    )
    func aliasScan(yaml: String, expected: Int) {
        #expect(YAMLFrontmatter.aliasCount(in: yaml) == expected)
    }
}

@Suite("Frontmatter rendering")
struct FrontmatterRenderingTests {
    private var tableOptions: RenderOptions {
        var options = RenderOptions()
        options.frontmatterDisplay = .table
        return options
    }

    @Test("hidden by default; body source lines keep file line numbers")
    func hidden() throws {
        let markdown = "---\ntitle: Doc\nlist:\n  - a\n---\n\n# One\n\ntext\n\n## Two\n"
        let rendered = HTMLRenderer().render(markdown)
        #expect(
            rendered.html
                == anchoredHeading(1, "one", "One") + "\n<p>text</p>\n" + anchoredHeading(2, "two", "Two") + "\n"
        )
        #expect(rendered.title == "Doc")
        #expect(rendered.frontmatter?.lineCount == 5)

        let extracted = try #require(Frontmatter.extract(from: markdown))
        let tree = MarkdownParser().parse(String(extracted.body), lineOffset: extracted.frontmatter.lineCount)
        #expect(headingLines(tree) == [7, 11])
        #expect(tree.children.first?.sourceRange?.start.column == 1)
        #expect(tree.sourceRange?.end.line == 11)
    }

    @Test("detection can be turned off (spec mode)")
    func disabled() {
        var options = RenderOptions()
        options.detectsFrontmatter = false
        let rendered = HTMLRenderer(options: options).render("---\ntitle: x\n---\n")
        #expect(rendered.frontmatter == nil)
        #expect(rendered.title == nil)
        #expect(
            rendered.html
                == "<hr />\n" + anchoredHeading(2, "title-x", "title: x") + "\n"
        )
    }

    @Test("title comes from a scalar title only")
    func title() {
        #expect(HTMLRenderer().render("---\ntitle: '  Spaced  '\n---\n").title == "Spaced")
        #expect(HTMLRenderer().render("---\ntitle: [a]\n---\n").title == nil)
        #expect(HTMLRenderer().render("---\ntitle: ''\n---\n").title == nil)
        #expect(HTMLRenderer().render("---\nTitle: x\n---\n").title == nil)
    }

    @Test("table mode renders keys, lists, and nested tables")
    func table() {
        let markdown = "---\ntitle: Doc\ntags: [a, b]\nempty:\nauthor:\n  name: Ada\n---\ntext\n"
        let html = HTMLRenderer(options: tableOptions).render(markdown).html
        #expect(
            html == """
                <table class="frontmatter">
                <tbody>
                <tr>
                <th>title</th>
                <td>Doc</td>
                </tr>
                <tr>
                <th>tags</th>
                <td>a, b</td>
                </tr>
                <tr>
                <th>empty</th>
                <td></td>
                </tr>
                <tr>
                <th>author</th>
                <td>
                <table>
                <tbody>
                <tr>
                <th>name</th>
                <td>Ada</td>
                </tr>
                </tbody>
                </table>
                </td>
                </tr>
                </tbody>
                </table>
                <p>text</p>

                """
        )
    }

    @Test("table mode escapes every key and value")
    func escaping() {
        let markdown = """
            ---
            "<b>key&": "<script>alert('x')</script>"
            list: ["<img src=x onerror=y>", "\\"q\\""]
            nested:
              "<i>": "&amp;"
            ---
            """
        let html = HTMLRenderer(options: tableOptions).render(markdown).html
        #expect(!html.contains("<script"))
        #expect(!html.contains("<img"))
        #expect(!html.contains("<b>"))
        #expect(!html.contains("<i>"))
        #expect(html.contains("<th>&lt;b&gt;key&amp;</th>"))
        #expect(html.contains("<td>&lt;script&gt;alert('x')&lt;/script&gt;</td>"))
        #expect(html.contains("<td>&lt;img src=x onerror=y&gt;, &quot;q&quot;</td>"))
        #expect(html.contains("<th>&lt;i&gt;</th>\n<td>&amp;amp;</td>"))
    }

    @Test("table mode shows TOML as an escaped code block")
    func tomlTable() {
        let html = HTMLRenderer(options: tableOptions).render("+++\ntitle = \"<x>\"\n+++\n# H\n").html
        let code =
            "<pre class=\"frontmatter\"><code class=\"language-toml\">title = &quot;&lt;x&gt;&quot;\n</code></pre>"
        #expect(html == code + "\n" + anchoredHeading(1, "h", "H") + "\n")
    }

    @Test("table mode shows nothing for empty YAML")
    func emptyTable() {
        #expect(HTMLRenderer(options: tableOptions).render("---\n---\ntext\n").html == "<p>text</p>\n")
    }

    @Test("HTMLDocument escapes a frontmatter title")
    func documentTitle() throws {
        let rendered = HTMLRenderer().render("---\ntitle: \"</title><script>x</script>\"\n---\n")
        let title = try #require(rendered.title)
        let html = HTMLDocument(title: title, body: rendered.html, theme: .github).html
        #expect(html.contains("<title>&lt;/title&gt;&lt;script&gt;x&lt;/script&gt;</title>"))
    }
}
