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

@Suite("HTMLRenderer: GFM footnotes")
struct GFMFootnoteTests {
    @Test("GitHub markup for a reference, the section, and the back-reference")
    func github() {
        #expect(
            html("a[^n]\n\n[^n]: Note.")
                == """
                <p>a<sup><a href="#fn-n" id="fnref-n" data-footnote-ref="" aria-describedby="footnote-label">1</a>\
                </sup></p>
                <section data-footnotes="" class="footnotes"><h2 id="footnote-label" class="sr-only">Footnotes</h2>
                <ol>
                <li id="fn-n">
                <p>Note. <a href="#fnref-n" data-footnote-backref="" aria-label="Back to reference 1" \
                class="data-footnote-backref">↩</a></p>
                </li>
                </ol>
                </section>

                """)
    }

    @Test("repeated references get suffixed ids and one back-link each")
    func multipleReferences() {
        let output = html("a[^x] b[^x] c[^x]\n\n[^x]: X")
        #expect(output.contains("id=\"fnref-x\""))
        #expect(output.contains("id=\"fnref-x-2\""))
        #expect(output.contains("id=\"fnref-x-3\""))
        #expect(output.components(separatedBy: "href=\"#fn-x\"").count == 4)
        #expect(
            output.contains(
                "<a href=\"#fnref-x-3\" data-footnote-backref=\"\" aria-label=\"Back to reference 1-3\" "
                    + "class=\"data-footnote-backref\">↩<sup>3</sup></a></p>"))
    }

    @Test("numbered by first reference; unreferenced definitions are left out")
    func numbering() {
        let output = html("a[^b] c[^a]\n\n[^a]: A\n\n[^b]: B\n\n[^unused]: U")
        #expect(
            output.contains(
                "href=\"#fn-b\" id=\"fnref-b\" data-footnote-ref=\"\" aria-describedby=\"footnote-label\">1<"))
        #expect(
            output.contains(
                "href=\"#fn-a\" id=\"fnref-a\" data-footnote-ref=\"\" aria-describedby=\"footnote-label\">2<"))
        let section = output.split(separator: "<section").last ?? ""
        #expect(
            section.range(of: "id=\"fn-b\"")?.lowerBound ?? section.endIndex
                < section.range(of: "id=\"fn-a\"")?.lowerBound ?? section.startIndex)
        #expect(!output.contains("unused"))
        #expect(!output.contains(">U"))
    }

    @Test("a reference without a definition is literal text, and no section is written")
    func missingDefinition() {
        #expect(html("a[^nope]") == "<p>a[^nope]</p>\n")
    }

    @Test("block content: back-links follow a trailing non-paragraph block")
    func blockContent() {
        #expect(
            html("a[^n]\n\n[^n]:\n    - one\n    - two\n\n    ```\n    code\n    ```")
                .hasSuffix(
                    """
                    <li id="fn-n">
                    <ul>
                    <li>one</li>
                    <li>two</li>
                    </ul>
                    <pre><code>code
                    </code></pre>
                    <a href="#fnref-n" data-footnote-backref="" aria-label="Back to reference 1" \
                    class="data-footnote-backref">↩</a>
                    </li>
                    </ol>
                    </section>

                    """))
    }

    @Test(
        "labels are user text: percent-encoded in ids and hrefs",
        arguments: ["\"><script>alert(1)</script>", "a&b'c", "ünï"]
    )
    func specialLabels(label: String) {
        let output = html("x[^\(label)]\n\n[^\(label)]: note")
        #expect(output.contains("<sup><a href=\"#fn-"))
        #expect(!output.contains("<script"))
        let attributes = output.matches(of: /(?:id|href)="(#?fn(?:ref)?-[^"]*)"/).map { String($0.1) }
        #expect(attributes.count == 4)
        for value in attributes {
            #expect(value.allSatisfy { $0.isASCII && !" <>'".contains($0) }, "\(value)")
        }
        // The reference and the definition agree, so the links resolve.
        #expect(Set(attributes.map { $0.replacing(/^#?fn(ref)?-/, with: "") }).count == 1)
    }

    @Test("cmark markup (spec mode) for references and back-links")
    func cmarkMarkup() {
        #expect(
            html("a[^n] b[^n]\n\n[^n]: N", markup: .cmark)
                == """
                <p>a<sup class="footnote-ref"><a href="#fn-n" id="fnref-n" data-footnote-ref>1</a></sup> \
                b<sup class="footnote-ref"><a href="#fn-n" id="fnref-n-2" data-footnote-ref>1</a></sup></p>
                <section class="footnotes" data-footnotes>
                <ol>
                <li id="fn-n">
                <p>N <a href="#fnref-n" class="footnote-backref" data-footnote-backref data-footnote-backref-idx="1" \
                aria-label="Back to reference 1">↩</a> <a href="#fnref-n-2" class="footnote-backref" \
                data-footnote-backref data-footnote-backref-idx="1-2" aria-label="Back to reference 1-2">↩\
                <sup class="footnote-ref">2</sup></a></p>
                </li>
                </ol>
                </section>

                """)
    }
}
