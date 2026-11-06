import Testing

@testable import MdvCore

/// Renders with heading anchors off, so heading markup matches cmark's.
private func html(_ markdown: String) -> String {
    var options = RenderOptions()
    options.headingAnchors = false
    return HTMLRenderer(options: options).render(markdown).html
}

@Suite("HTMLRenderer: CommonMark blocks")
struct HTMLRendererBlockTests {
    @Test("empty input renders nothing")
    func empty() {
        #expect(html("").isEmpty)
    }

    @Test("ATX and setext headings")
    func headings() {
        #expect(html("# One\n###### Six") == "<h1>One</h1>\n<h6>Six</h6>\n")
        #expect(html("Two\n---") == "<h2>Two</h2>\n")
    }

    @Test("paragraphs with soft and hard breaks")
    func paragraphs() {
        #expect(html("a\nb") == "<p>a\nb</p>\n")
        #expect(html("a  \nb\\\nc") == "<p>a<br />\nb<br />\nc</p>\n")
        #expect(html("one\n\ntwo") == "<p>one</p>\n<p>two</p>\n")
    }

    @Test("block quotes")
    func blockQuote() {
        #expect(
            html("> quote\n> > nested")
                == "<blockquote>\n<p>quote</p>\n<blockquote>\n<p>nested</p>\n</blockquote>\n</blockquote>\n")
    }

    @Test("tight bullet list")
    func tightList() {
        #expect(html("- a\n- b") == "<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n")
    }

    @Test("loose ordered list with a start number")
    func looseOrderedList() {
        #expect(html("3. a\n\n4. b") == "<ol start=\"3\">\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ol>\n")
        #expect(html("1) a") == "<ol>\n<li>a</li>\n</ol>\n")
    }

    @Test("nested lists keep tightness per list")
    func nestedList() {
        #expect(html("- a\n  - b\n- c") == "<ul>\n<li>a\n<ul>\n<li>b</li>\n</ul>\n</li>\n<li>c</li>\n</ul>\n")
    }

    @Test("indented code block")
    func indentedCode() {
        #expect(html("    let x = 1 < 2\n") == "<pre><code>let x = 1 &lt; 2\n</code></pre>\n")
    }

    @Test("fenced code block uses the first word of the info string")
    func fencedCode() {
        #expect(
            html("```swift linenos\nprint(\"hi\")\n```")
                == "<pre><code class=\"language-swift\">print(&quot;hi&quot;)\n</code></pre>\n")
        #expect(html("~~~\nplain\n~~~") == "<pre><code>plain\n</code></pre>\n")
        #expect(html("```a\"b\nx\n```") == "<pre><code class=\"language-a&quot;b\">x\n</code></pre>\n")
    }

    @Test("thematic break")
    func thematicBreak() {
        #expect(html("***") == "<hr />\n")
    }

    @Test("HTML blocks pass through unchanged when sanitizing is off")
    func htmlBlock() {
        let renderer = HTMLRenderer(options: RenderOptions(sanitize: false))
        #expect(renderer.render("<div class=\"x\">\n*hi*\n</div>").html == "<div class=\"x\">\n*hi*\n</div>\n")
    }

    @Test("HTML blocks are sanitized by default")
    func htmlBlockSanitized() {
        #expect(html("<div class=\"x\">\n*hi*\n</div>") == "<div>\n*hi*\n</div>\n")
    }
}

@Suite("HTMLRenderer: CommonMark inlines")
struct HTMLRendererInlineTests {
    @Test("emphasis and strong")
    func emphasis() {
        #expect(html("*a* _b_ **c** __d__") == "<p><em>a</em> <em>b</em> <strong>c</strong> <strong>d</strong></p>\n")
        #expect(html("***x***") == "<p><em><strong>x</strong></em></p>\n")
    }

    @Test("directly nested strong collapses like cmark")
    func nestedStrong() {
        #expect(html("****x****") == "<p><strong>x</strong></p>\n")
    }

    @Test("code spans are escaped")
    func codeSpan() {
        #expect(html("`<a> & b`") == "<p><code>&lt;a&gt; &amp; b</code></p>\n")
    }

    @Test("inline links with and without titles")
    func links() {
        #expect(
            html("[a](/url \"T & \\\"q\\\"\")") == "<p><a href=\"/url\" title=\"T &amp; &quot;q&quot;\">a</a></p>\n")
        #expect(html("[a](</my url>)") == "<p><a href=\"/my%20url\">a</a></p>\n")
    }

    @Test("reference links")
    func referenceLink() {
        #expect(html("[a][ref]\n\n[ref]: /x 'T'") == "<p><a href=\"/x\" title=\"T\">a</a></p>\n")
    }

    @Test("autolinks")
    func autolinks() {
        #expect(
            html("<https://example.com/?a=1&b=2>")
                == "<p><a href=\"https://example.com/?a=1&amp;b=2\">https://example.com/?a=1&amp;b=2</a></p>\n")
        #expect(html("<me@example.com>") == "<p><a href=\"mailto:me@example.com\">me@example.com</a></p>\n")
    }

    @Test("images use plain-text alt and an optional title")
    func images() {
        #expect(html("![a *b* `c`](/i.png \"t\")") == "<p><img src=\"/i.png\" alt=\"a b c\" title=\"t\" /></p>\n")
        #expect(html("![x\ny](i.png)") == "<p><img src=\"i.png\" alt=\"x y\" /></p>\n")
    }

    @Test("inline raw HTML passes through unchanged when sanitizing is off")
    func inlineHTML() {
        let renderer = HTMLRenderer(options: RenderOptions(sanitize: false))
        #expect(renderer.render("a <span onclick=\"x\">b").html == "<p>a <span onclick=\"x\">b</p>\n")
        #expect(html("a <span title=\"x\">b</span>") == "<p>a <span title=\"x\">b</span></p>\n")
    }

    @Test("backslash escapes")
    func backslashEscapes() {
        #expect(html("\\*not emphasis\\*") == "<p>*not emphasis*</p>\n")
    }
}

@Suite("HTMLRenderer: escaping and entities")
struct HTMLRendererEscapingTests {
    @Test("text escapes & < > \" but not ' or /")
    func textEscaping() {
        #expect(html("a & b < c > d \"e\" 'f' /g") == "<p>a &amp; b &lt; c &gt; d &quot;e&quot; 'f' /g</p>\n")
    }

    @Test("URLs are percent-encoded like cmark")
    func urlEncoding() {
        #expect(html("[a](/ä?q=1&r='s'#[x])") == "<p><a href=\"/%C3%A4?q=1&amp;r=&#x27;s&#x27;#%5Bx%5D\">a</a></p>\n")
        // Existing escapes are kept, not double-encoded.
        #expect(html("[a](/a%20b)") == "<p><a href=\"/a%20b\">a</a></p>\n")
        #expect(html("[a](/\"<>\\\\{}|^`)") == "<p><a href=\"/%22%3C%3E%5C%7B%7D%7C%5E%60\">a</a></p>\n")
    }

    @Test("named and numeric entities are decoded, then re-escaped where needed")
    func entities() {
        #expect(html("&copy; &#35; &#x22; &amp; &lt;") == "<p>© # &quot; &amp; &lt;</p>\n")
        #expect(html("&nosuchentity; & &#0;") == "<p>&amp;nosuchentity; &amp; \u{FFFD}</p>\n")
        #expect(
            html("[a](/f&ouml;o \"&quot;t&quot;\")") == "<p><a href=\"/f%C3%B6o\" title=\"&quot;t&quot;\">a</a></p>\n")
        #expect(html("`&amp;`") == "<p><code>&amp;amp;</code></p>\n")
    }

    @Test("no smart punctuation: quotes, dashes, and ellipses stay as typed")
    func noSmartPunctuation() {
        let output = html("\"x\" 'y' -- --- ...")
        #expect(output == "<p>&quot;x&quot; 'y' -- --- ...</p>\n")
        for curly in ["\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}", "\u{2013}", "\u{2014}", "\u{2026}"] {
            #expect(!output.contains(curly))
        }
    }

    @Test(
        "dangerous URL schemes are dropped like cmark's safe mode",
        arguments: [
            "javascript:alert(1)", "JavaScript:alert(1)", "vbscript:x", "file:///etc/passwd", "data:text/html,x",
        ]
    )
    func dangerousURLs(url: String) {
        #expect(html("[a](\(url))") == "<p><a href=\"\">a</a></p>\n")
        #expect(html("![a](\(url))") == "<p><img src=\"\" alt=\"a\" /></p>\n")
    }

    @Test("safe data: images are kept")
    func dataImage() {
        #expect(
            html("![a](data:image/png;base64,AAA=)") == "<p><img src=\"data:image/png;base64,AAA=\" alt=\"a\" /></p>\n")
    }
}

@Suite("HTMLRenderer: API")
struct HTMLRendererAPITests {
    @Test("render returns an HTML fragment, title, and headings")
    func renderedDocument() {
        let document = HTMLRenderer().render("# Title")
        #expect(
            document
                == RenderedDocument(
                    html: "<h1 id=\"title\"><a class=\"anchor\" aria-hidden=\"true\" href=\"#title\"></a>Title</h1>\n",
                    title: "Title",
                    headings: [Heading(level: 1, text: "Title", slug: "title", sourceLine: 1)]
                ))
    }

    @Test("renders a pre-parsed tree")
    func renderTree() {
        let tree = MarkdownNode(
            .document, children: [MarkdownNode(.paragraph, children: [MarkdownNode(.text("<hi>"))])])
        #expect(HTMLRenderer().html(for: tree) == "<p>&lt;hi&gt;</p>\n")
    }

    @Test("GFM syntax is literal text when its extension is off")
    func extensionsOff() {
        #expect(HTMLRenderer(options: RenderOptions(extensions: [])).render("~~x~~").html == "<p>~~x~~</p>\n")
    }

    @Test("default options render GFM with GitHub markup")
    func defaults() {
        #expect(RenderOptions().extensions == MarkdownExtension.gfm)
        #expect(MarkdownExtension.gfm == Set(MarkdownExtension.allCases))
        #expect(RenderOptions().gfmMarkup == .github)
        #expect(RenderOptions.spec.gfmMarkup == .cmark)
    }

    @Test("deeply nested input renders without crashing")
    func deepNesting() {
        let output = html(String(repeating: ">", count: 50_000) + " deep")
        #expect(output.contains("deep"))
        #expect(output.components(separatedBy: "<blockquote>").count - 1 < MarkdownParser.maximumNestingDepth)
    }
}
