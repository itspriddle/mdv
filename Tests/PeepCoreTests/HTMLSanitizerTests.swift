import Testing

@testable import PeepCore

func sanitized(_ html: String) -> String {
    HTMLSanitizer().sanitize(fragment: html)
}

func rendered(_ markdown: String) -> String {
    HTMLRenderer().render(markdown).html
}

@Suite("HTMLSanitizer: XSS corpus")
struct HTMLSanitizerXSSTests {
    @Test("fragments sanitize to safe output", arguments: xssCorpus)
    func fragment(_ input: String) {
        let output = sanitized(input)
        #expect(OutputChecker.problems(in: output).isEmpty, "\(output)")
    }

    @Test("Markdown with the pattern inline and as a block renders safely", arguments: xssCorpus)
    func markdown(_ input: String) {
        for markdown in [input, "text \(input) text", "> - \(input)\n\n\(input)"] {
            let output = rendered(markdown)
            #expect(OutputChecker.problems(in: output, isMarkdown: true).isEmpty, "\(output)")
        }
    }

    @Test("obfuscated javascript: URLs are removed")
    func obfuscatedSchemes() {
        #expect(sanitized(#"<a href="jav&#x09;ascript:alert(1)">x</a>"#) == "<a>x</a>")
        #expect(sanitized(#"<a href="javascript&colon;alert(1)">x</a>"#) == "<a>x</a>")
        #expect(sanitized(#"<a href="&#106;avascript:alert(1)">x</a>"#) == "<a>x</a>")
        #expect(sanitized(#"<a href=" javascript:alert(1)">x</a>"#) == "<a>x</a>")
        #expect(sanitized("<a href=\"java\u{0}script:alert(1)\">x</a>") == "<a>x</a>")
        #expect(sanitized(#"<a href="data:text/html,x">x</a>"#) == "<a>x</a>")
        #expect(sanitized(#"<a href="VBScript:x">x</a>"#) == "<a>x</a>")
        #expect(sanitized(#"<img src="mailto:a@b.c">"#) == "<img>")
    }

    @Test("event handlers and inline styles are removed")
    func eventHandlers() {
        #expect(sanitized("<img src=x onerror=alert(1)>") == #"<img src="x">"#)
        #expect(sanitized("<svg onload=alert(1)>text</svg>after") == "after")
        #expect(sanitized("<img/src=x/onerror=alert(1)>") == #"<img src="x/onerror=alert(1)">"#)
        #expect(sanitized(#"<p style="color:red" onclick="x()">p</p>"#) == "<p>p</p>")
    }

    @Test("script-like elements are removed with their content")
    func droppedContent() {
        #expect(sanitized("a<script>alert(1)</script>b") == "ab")
        #expect(sanitized("a<script>x = '</div>'</script>b") == "ab")
        #expect(sanitized("a<style>p{}</style>b<iframe src=x>c</iframe>d") == "abd")
        #expect(sanitized("a<object><object>x</object>y</object>b") == "ab")
        #expect(sanitized("a<script>never closed <b>bold</b>") == "a")
        #expect(sanitized("a<!-- <script>x</script> -->b") == "ab")
        #expect(sanitized("a<!--><b>x</b>-->") == "a<b>x</b>--&gt;")
    }

    @Test("unknown elements are removed but keep their text")
    func unknownElements() {
        #expect(sanitized("<foo>bar</foo>") == "bar")
        #expect(sanitized("<input value=x>after") == "after")
        #expect(sanitized("<u>under</u>") == "under")
    }

    @Test("text and attribute values are re-escaped")
    func escaping() {
        #expect(sanitized("a < b > c & d &amp; &eacute; &#60;") == "a &lt; b &gt; c &amp; d &amp; &eacute; &#60;")
        #expect(
            sanitized(#"<img alt="&quot;&lt;x&gt; &copy; &#9731; a&b">"#)
                == #"<img alt="&quot;&lt;x&gt; &copy; &#x2603; a&b">"#)
        #expect(sanitized("<img alt='say \"hi\"'>") == #"<img alt="say &quot;hi&quot;">"#)
        #expect(sanitized("<img alt=a&lt=b>") == #"<img alt="a&lt=b">"#)
    }
}

// MARK: - Allowed markup

@Suite("HTMLSanitizer: allowed markup")
struct HTMLSanitizerAllowedTests {
    @Test("common README HTML survives intact")
    func readmeHTML() {
        let markdown = """
            <p align="center">
              <img src="docs/logo.png" width="200" height="100" alt="Logo">
            </p>

            <details open>
            <summary>Show <kbd>Ctrl</kbd>+<kbd>C</kbd></summary>

            E = mc<sup>2</sup>, H<sub>2</sub>O

            </details>
            """
        #expect(
            rendered(markdown) == """
                <p align="center">
                  <img src="docs/logo.png" width="200" height="100" alt="Logo">
                </p>
                <details open>
                <summary>Show <kbd>Ctrl</kbd>+<kbd>C</kbd></summary>
                <p>E = mc<sup>2</sup>, H<sub>2</sub>O</p>
                </details>

                """)
    }

    @Test("links keep http, https, mailto, relative, and fragment URLs")
    func allowedURLs() {
        for url in ["https://example.com/a?b=c#d", "http://x", "mailto:a@b.c", "docs/a.md", "/abs", "#frag", "?q=a:b"] {
            #expect(sanitized(#"<a href="\#(url)">x</a>"#) == #"<a href="\#(url)">x</a>"#)
        }
        #expect(
            sanitized(#"<img src="https://e.com/i.png" loading="lazy">"#)
                == #"<img src="https://e.com/i.png" loading="lazy">"#)
        #expect(
            sanitized(#"<a href="https://e.com/?a=1&amp;b=2">x</a>"#) == #"<a href="https://e.com/?a=1&amp;b=2">x</a>"#)
    }

    @Test("id and name get the user-content- prefix")
    func userContentPrefix() {
        #expect(sanitized(#"<a name="top" id="x"></a>"#) == #"<a name="user-content-top" id="user-content-x"></a>"#)
        #expect(sanitized(#"<span id="user-content-x"></span>"#) == #"<span id="user-content-x"></span>"#)
        #expect(sanitized(#"<span id="" name></span>"#) == "<span></span>")
    }

    @Test("tables, lists, and picture sources")
    func structures() {
        #expect(
            sanitized("<table><tr><th colspan=2>h</th></tr><tr><td>c</td></tr></table>")
                == #"<table><tr><th colspan="2">h</th></tr><tr><td>c</td></tr></table>"#)
        #expect(
            sanitized("<ul><li>a</li></ul><dl><dt>t</dt><dd>d</dd></dl>")
                == "<ul><li>a</li></ul><dl><dt>t</dt><dd>d</dd></dl>")
        #expect(
            sanitized(
                #"<picture><source srcset="a.png 1x, https://e.com/b.png 2x" media="(x)"><img src="a.png"></picture>"#)
                == #"<picture><source srcset="a.png 1x, https://e.com/b.png 2x" media="(x)"><img src="a.png"></picture>"#
        )
    }

    @Test("void and self-closing tags")
    func voidTags() {
        #expect(sanitized("a<br>b<br/>c<hr />") == "a<br>b<br />c<hr />")
        #expect(sanitized("<div/>x") == "<div>x</div>")
        #expect(sanitized("a</br></img>b") == "ab")
    }
}

// MARK: - Balancing

@Suite("HTMLSanitizer: balancing")
struct HTMLSanitizerBalanceTests {
    @Test("unclosed inline tags close at the end of their paragraph")
    func unclosedInline() {
        #expect(rendered("a <b>bold\n\nnext") == "<p>a <b>bold</b></p>\n<p>next</p>\n")
        #expect(rendered("*a <span>b*") == "<p><em>a <span>b</span></em></p>\n")
    }

    @Test("stray end tags can't close the containing Markdown element")
    func strayEndTags() {
        #expect(rendered("> a </blockquote> b") == "<blockquote>\n<p>a  b</p>\n</blockquote>\n")
        #expect(rendered("- a </li></ul> b") == "<ul>\n<li>a  b</li>\n</ul>\n")
        #expect(rendered("*a</em> b*") == "<p><em>a b</em></p>\n")
    }

    @Test("an end tag closes elements opened after its start tag")
    func misnested() {
        #expect(sanitized("<b><i>x</b>y</i>") == "<b><i>x</i></b>y")
    }

    @Test("table parts and list items need an open parent")
    func requiredAncestors() {
        #expect(sanitized("<td>a</td><li>b</li><dd>c</dd><tr>d</tr>") == "abcd")
        #expect(sanitized("<table><td>a</td></table>") == "<table>a</table>")
    }

    @Test("raw HTML blocks wrap Markdown content between them")
    func blocksAroundMarkdown() {
        let markdown = "<div align=\"right\">\n\n**md**\n\n</div>\n\nafter"
        #expect(rendered(markdown) == "<div align=\"right\">\n<p><strong>md</strong></p>\n</div>\n<p>after</p>\n")
        #expect(rendered("<div>\n\nunclosed") == "<div>\n<p>unclosed</p>\n</div>\n")
        #expect(rendered("> <div>\n\n</div>") == "<blockquote>\n<div>\n</div>\n</blockquote>\n")
    }

    @Test("inline script content between separate HTML nodes is dropped")
    func inlineScript() {
        #expect(rendered("a <script>alert(*1*)</script> b") == "<p>a  b</p>\n")
        #expect(rendered("a <style>*x*\nb\n\nc") == "<p>a </p>\n<p>c</p>\n")
        #expect(rendered("<form>\n\n# heading\n\n</form>\n\nafter") == "<p>after</p>\n")
    }

    @Test("raw HTML left open in the body can't wrap or hide the footnotes")
    func footnotesAfterOpenHTML() {
        let wrapped = rendered("x[^1]\n\n<details>\n\n[^1]: note")
        #expect(wrapped.contains("</details>\n<section data-footnotes"))
        #expect(wrapped.hasSuffix("</li>\n</ol>\n</section>\n"))

        let hidden = rendered("x[^1]\n\n<svg>\n\nhidden\n\n[^1]: note")
        #expect(!hidden.contains("hidden"))
        #expect(hidden.contains("<li id=\"fn-1\">\n<p>note "))
    }

    @Test("sanitizing a tree leaves non-HTML nodes alone and skips image alt text")
    func tree() {
        let tree = MarkdownNode(
            .document,
            children: [
                MarkdownNode(
                    .paragraph,
                    children: [
                        MarkdownNode(.image(source: "i.png", title: nil), children: [MarkdownNode(.htmlInline("<b>"))]),
                        MarkdownNode(.htmlInline("<b onclick=x>")),
                        MarkdownNode(.text("t")),
                    ])
            ])
        let expected = MarkdownNode(
            .document,
            children: [
                MarkdownNode(
                    .paragraph,
                    children: [
                        MarkdownNode(.image(source: "i.png", title: nil), children: [MarkdownNode(.htmlInline("<b>"))]),
                        MarkdownNode(.htmlInline("<b>")),
                        MarkdownNode(.text("t")),
                        MarkdownNode(.htmlInline("</b>")),
                    ])
            ])
        #expect(HTMLSanitizer().sanitize(tree) == expected)
        #expect(HTMLRenderer().html(for: tree) == "<p><img src=\"i.png\" alt=\"&lt;b&gt;\" /><b>t</b></p>\n")
    }
}
