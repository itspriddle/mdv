import Testing

@testable import MdvCore

private func html(_ markdown: String, markup: GFMMarkup = .github) -> String {
    var options = RenderOptions()
    options.gfmMarkup = markup
    return HTMLRenderer(options: options).render(markdown).html
}

@Suite("HTMLRenderer: GFM tables")
struct GFMTableTests {
    @Test("column alignment becomes an align attribute on every cell of the column")
    func alignment() {
        #expect(
            html("| a | b | c | d |\n| :- | :-: | -: | - |\n| 1 | 2 | 3 | 4 |")
                == """
                <table>
                <thead>
                <tr>
                <th align="left">a</th>
                <th align="center">b</th>
                <th align="right">c</th>
                <th>d</th>
                </tr>
                </thead>
                <tbody>
                <tr>
                <td align="left">1</td>
                <td align="center">2</td>
                <td align="right">3</td>
                <td>4</td>
                </tr>
                </tbody>
                </table>

                """)
    }

    @Test("a table with no body rows has no tbody")
    func emptyBody() {
        #expect(html("| a |\n| - |") == "<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n</table>\n")
    }

    @Test("escaped pipes and inline content in cells; missing cells are empty, extra cells dropped")
    func cells() {
        let output = html("| a | b |\n| - | - |\n| x \\| *y* | `c\\|d` |\n| 1 |\n| 1 | 2 | 3 |")
        #expect(output.contains("<td>x | <em>y</em></td>\n<td><code>c|d</code></td>"))
        #expect(output.contains("<tr>\n<td>1</td>\n<td></td>\n</tr>"))
        #expect(output.contains("<tr>\n<td>1</td>\n<td>2</td>\n</tr>"))
        #expect(output.components(separatedBy: "<tbody>").count == 2)
    }

    @Test("tables are literal text without the extension")
    func disabled() {
        let output = HTMLRenderer(options: RenderOptions(extensions: [])).render("| a |\n| - |").html
        #expect(output == "<p>| a |\n| - |</p>\n")
    }
}

@Suite("HTMLRenderer: GFM strikethrough and autolinks")
struct GFMInlineTests {
    @Test("one or two tildes strike through, three do not")
    func strikethrough() {
        #expect(html("~a~ ~~b~~ ~~~c~~~") == "<p><del>a</del> <del>b</del> ~~~c~~~</p>\n")
        #expect(html("~~*x*~~") == "<p><del><em>x</em></del></p>\n")
    }

    @Test(
        "extended autolinks follow the GFM trailing punctuation and parenthesis rules",
        arguments: [
            ("www.example.com.", "<a href=\"http://www.example.com\">www.example.com</a>."),
            ("(https://x.y)", "(<a href=\"https://x.y\">https://x.y</a>)"),
            ("http://x.y/(a)", "<a href=\"http://x.y/(a)\">http://x.y/(a)</a>"),
            ("www.x.y/a_(b))", "<a href=\"http://www.x.y/a_(b)\">www.x.y/a_(b)</a>)"),
            ("https://x.y/?a=1&b=2,", "<a href=\"https://x.y/?a=1&amp;b=2\">https://x.y/?a=1&amp;b=2</a>,"),
            ("https://x.y/a&amp;", "<a href=\"https://x.y/a\">https://x.y/a</a>&amp;"),
            ("a.b-c_d@x.y.", "<a href=\"mailto:a.b-c_d@x.y\">a.b-c_d@x.y</a>."),
            ("foo@bar", "foo@bar"),
        ]
    )
    func autolinks(markdown: String, expected: String) {
        #expect(html(markdown) == "<p>\(expected)</p>\n")
    }

    @Test("autolinked javascript: URLs are not produced")
    func unsafeAutolink() {
        #expect(!html("javascript:alert(1) www.x.y").contains("href=\"javascript"))
    }
}

@Suite("HTMLRenderer: GFM task lists")
struct GFMTaskListTests {
    @Test("GitHub markup: classes, disabled checkboxes, and nested task lists")
    func nested() {
        #expect(
            html("- [ ] a\n- [x] b\n  - [X] c\n- d")
                == """
                <ul class="contains-task-list">
                <li class="task-list-item"><input type="checkbox" disabled="" class="task-list-item-checkbox" \
                aria-label="Incomplete task"> a</li>
                <li class="task-list-item"><input type="checkbox" disabled="" class="task-list-item-checkbox" \
                aria-label="Completed task" checked=""> b
                <ul class="contains-task-list">
                <li class="task-list-item"><input type="checkbox" disabled="" class="task-list-item-checkbox" \
                aria-label="Completed task" checked=""> c</li>
                </ul>
                </li>
                <li>d</li>
                </ul>

                """)
    }

    @Test("GitHub markup: in loose lists the checkbox goes inside the first paragraph")
    func loose() {
        #expect(
            html("1. [x] a\n\n   b")
                == """
                <ol class="contains-task-list">
                <li class="task-list-item">
                <p><input type="checkbox" disabled="" class="task-list-item-checkbox" \
                aria-label="Completed task" checked=""> a</p>
                <p>b</p>
                </li>
                </ol>

                """)
    }

    @Test("lists without task items get no class")
    func plainList() {
        #expect(html("- [@] a\n- b") == "<ul>\n<li>[@] a</li>\n<li>b</li>\n</ul>\n")
    }

    @Test("cmark markup (spec mode): bare checkboxes before the item content")
    func cmarkMarkup() {
        #expect(
            html("- [ ] a\n- [x] b\n\n  c", markup: .cmark)
                == """
                <ul>
                <li><input type="checkbox" disabled="" /> \n<p>a</p>
                </li>
                <li><input type="checkbox" checked="" disabled="" /> \n<p>b</p>
                <p>c</p>
                </li>
                </ul>

                """)
    }
}
