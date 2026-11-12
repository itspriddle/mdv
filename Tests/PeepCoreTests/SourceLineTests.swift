import Testing

@testable import PeepCore

/// Renders with source lines on and heading anchors off.
private func annotated(_ markdown: String, markup: GFMMarkup = .github) -> String {
    var options = RenderOptions()
    options.sourceLines = true
    options.headingAnchors = false
    options.highlighting = false
    options.gfmMarkup = markup
    return HTMLRenderer(options: options).render(markdown).html
}

@Suite("HTMLRenderer: source line annotations")
struct SourceLineTests {
    @Test("off by default and in spec mode")
    func offByDefault() {
        #expect(!RenderOptions().sourceLines)
        #expect(!RenderOptions.spec.sourceLines)
        #expect(
            HTMLRenderer().render("# a\n\nb").html
                == "<h1 id=\"a\"><a class=\"anchor\" aria-hidden=\"true\" href=\"#a\"></a>a</h1>\n<p>b</p>\n")
    }

    @Test("ATX and setext headings use their first line")
    func headings() {
        #expect(
            annotated("# One\n\nTwo\n===\n\nThree\n---\n###### Six")
                == "<h1 data-source-line=\"1\">One</h1>\n<h1 data-source-line=\"3\">Two</h1>\n"
                + "<h2 data-source-line=\"6\">Three</h2>\n<h6 data-source-line=\"8\">Six</h6>\n")
    }

    @Test("headings with anchors keep the id first")
    func anchoredHeading() {
        var options = RenderOptions()
        options.sourceLines = true
        #expect(
            HTMLRenderer(options: options).render("\n## Hi").html
                == "<h2 id=\"hi\" data-source-line=\"2\">"
                + "<a class=\"anchor\" aria-hidden=\"true\" href=\"#hi\"></a>Hi</h2>\n"
        )
    }

    @Test("multi-line paragraphs use their first line")
    func paragraphs() {
        #expect(
            annotated("one\ntwo\nthree\n\nfour")
                == "<p data-source-line=\"1\">one\ntwo\nthree</p>\n<p data-source-line=\"5\">four</p>\n")
    }

    @Test("block quotes, code blocks, and thematic breaks")
    func blocks() {
        #expect(
            annotated("> quote\n> more\n\n```swift\nlet x = 1\n```\n\n    indented\n\n***")
                == "<blockquote data-source-line=\"1\">\n<p data-source-line=\"1\">quote\nmore</p>\n</blockquote>\n"
                + "<pre data-source-line=\"4\"><code class=\"language-swift\">let x = 1\n</code></pre>\n"
                + "<pre data-source-line=\"8\"><code>indented\n</code></pre>\n"
                + "<hr data-source-line=\"10\" />\n")
    }

    @Test("highlighted code blocks keep the line on pre")
    func highlightedCode() {
        var options = RenderOptions()
        options.sourceLines = true
        options.headingAnchors = false
        let html = HTMLRenderer(options: options).render("Text\n\n```swift\nlet x = 1\n```").html
        #expect(
            html.hasPrefix(
                "<p data-source-line=\"1\">Text</p>\n<pre data-source-line=\"3\"><code class=\"language-swift\">"))
        #expect(html.contains("<span class=\"hljs-keyword\">let</span>"))
    }

    @Test("nested tight and loose lists")
    func nestedLists() {
        let markdown = """
            1. one
            2. two
               - nested
               - nested again

                 loose paragraph
            """
        #expect(
            annotated(markdown)
                == "<ol data-source-line=\"1\">\n<li data-source-line=\"1\">one</li>\n"
                + "<li data-source-line=\"2\">two\n"
                + "<ul data-source-line=\"3\">\n"
                + "<li data-source-line=\"3\">\n<p data-source-line=\"3\">nested</p>\n</li>\n"
                + "<li data-source-line=\"4\">\n<p data-source-line=\"4\">nested again</p>\n"
                + "<p data-source-line=\"6\">loose paragraph</p>\n</li>\n</ul>\n</li>\n</ol>\n")
    }

    @Test("ordered list start and task list class come before the line")
    func listAttributes() {
        #expect(
            annotated("3. x")
                == "<ol start=\"3\" data-source-line=\"1\">\n<li data-source-line=\"1\">x</li>\n</ol>\n")
    }

    @Test("task items in GitHub and cmark markup")
    func taskItems() {
        #expect(
            annotated("- [ ] a\n- [x] b")
                == "<ul class=\"contains-task-list\" data-source-line=\"1\">\n"
                + "<li class=\"task-list-item\" data-source-line=\"1\"><input type=\"checkbox\" disabled=\"\" "
                + "class=\"task-list-item-checkbox\" aria-label=\"Incomplete task\"> a</li>\n"
                + "<li class=\"task-list-item\" data-source-line=\"2\"><input type=\"checkbox\" disabled=\"\" "
                + "class=\"task-list-item-checkbox\" aria-label=\"Completed task\" checked=\"\"> b</li>\n</ul>\n")
        #expect(
            annotated("- [x] a", markup: .cmark)
                == "<ul data-source-line=\"1\">\n<li data-source-line=\"1\">"
                + "<input type=\"checkbox\" checked=\"\" disabled=\"\" /> a</li>\n</ul>\n")
    }

    @Test("tables and rows, but not cells")
    func tables() {
        #expect(
            annotated("text\n\n| a | b |\n| - | - |\n| 1 | 2 |\n| 3 | 4 |")
                == "<p data-source-line=\"1\">text</p>\n<table data-source-line=\"3\">\n<thead>\n"
                + "<tr data-source-line=\"3\">\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n"
                + "<tr data-source-line=\"5\">\n<td>1</td>\n<td>2</td>\n</tr>\n"
                + "<tr data-source-line=\"6\">\n<td>3</td>\n<td>4</td>\n</tr>\n</tbody>\n</table>\n")
    }

    @Test("footnote items")
    func footnotes() {
        let html = annotated("a[^1] b[^n]\n\n[^1]: one\n\n[^n]:\n    > quoted")
        #expect(html.contains("<li id=\"fn-1\" data-source-line=\"3\">\n<p data-source-line=\"3\">one "))
        #expect(html.contains("<li id=\"fn-n\" data-source-line=\"5\">\n<blockquote data-source-line=\"6\">"))
        #expect(!html.contains("<section data-footnotes=\"\" class=\"footnotes\" data-source-line"))
    }

    @Test("raw HTML blocks are not annotated or wrapped")
    func rawHTML() {
        #expect(
            annotated("<div>\nraw\n</div>\n\nafter")
                == "<div>\nraw\n</div>\n<p data-source-line=\"5\">after</p>\n")
    }

    @Test("lines count from the top of the file, past frontmatter")
    func frontmatter() {
        #expect(
            annotated("---\ntitle: T\nmore: x\n---\n# Heading\n\ntext")
                == "<h1 data-source-line=\"5\">Heading</h1>\n<p data-source-line=\"7\">text</p>\n")
        #expect(annotated("+++\na = 1\n+++\n\ntext") == "<p data-source-line=\"5\">text</p>\n")
    }

    @Test("CRLF line endings count as one line each")
    func lineEndings() {
        let expected =
            "<h1 data-source-line=\"4\">Heading</h1>\n"
            + "<ul data-source-line=\"6\">\n"
            + "<li data-source-line=\"6\">a</li>\n<li data-source-line=\"7\">b</li>\n</ul>\n"
            + "<p data-source-line=\"9\">x\ny</p>\n"
        let unix = "---\ntitle: T\n---\n# Heading\n\n- a\n- b\n\nx\ny\n"
        #expect(annotated(unix) == expected)
        #expect(annotated(unix.replacingOccurrences(of: "\n", with: "\r\n")) == expected)
    }

    @Test("trees without source positions are not annotated")
    func noPositions() {
        var options = RenderOptions()
        options.sourceLines = true
        let tree = MarkdownNode(.document, children: [MarkdownNode(.paragraph, children: [])])
        #expect(HTMLRenderer(options: options).html(for: tree) == "<p></p>\n")
    }
}
