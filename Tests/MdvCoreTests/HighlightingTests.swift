import Foundation
import Synchronization
import Testing

@testable import MdvCore

/// Renders with heading anchors off and the shared highlight.js highlighter.
private func highlighted(_ markdown: String, highlighter: (any SyntaxHighlighter)? = HighlightJSHighlighter.shared)
    -> String
{
    var options = RenderOptions()
    options.headingAnchors = false
    return HTMLRenderer(options: options, highlighter: highlighter).render(markdown).html
}

private func fence(_ language: String, _ code: String) -> String {
    "```\(language)\n\(code)\n```\n"
}

/// Returns canned output and counts calls.
private final class StubHighlighter: SyntaxHighlighter {
    private let calls = Mutex(0)
    private let output: @Sendable (String, String) -> String?

    init(_ output: @escaping @Sendable (_ code: String, _ language: String) -> String?) {
        self.output = output
    }

    var callCount: Int { calls.withLock { $0 } }

    func highlight(_ code: String, language: String) -> String? {
        calls.withLock { $0 += 1 }
        return output(code, language)
    }
}

@Suite("Syntax highlighting")
struct HighlightingTests {
    @Test(
        "common languages produce hljs spans",
        arguments: [
            ("swift", "let x = 1 // one"),
            ("js", "const f = (a) => a + 1;"),
            ("javascript", "function f() { return null; }"),
            ("diff", "- old\n+ new"),
            ("Swift", "struct S {}"),
            ("dockerfile", "FROM alpine:3\nRUN echo hi"),
            ("elixir", "defmodule M do\nend"),
        ]
    )
    func highlights(language: String, code: String) {
        let html = highlighted(fence(language, code))
        #expect(html.hasPrefix("<pre><code class=\"language-\(language)\"><span class=\"hljs-"))
        #expect(html.hasSuffix("</code></pre>\n"))
    }

    @Test("an unknown language and no language render plain escaped code")
    func plain() {
        #expect(
            highlighted(fence("nope", "let <x> = 1"))
                == "<pre><code class=\"language-nope\">let &lt;x&gt; = 1\n</code></pre>\n"
        )
        #expect(highlighted(fence("", "let x = 1")) == "<pre><code>let x = 1\n</code></pre>\n")
        #expect(highlighted("    let x = 1\n") == "<pre><code>let x = 1\n</code></pre>\n")
    }

    @Test("only the info string's first word picks the language; there is no auto-detection")
    func languageFromFirstWord() {
        #expect(highlighted(fence("swift linenos", "let x = 1")).contains("hljs-keyword"))
        #expect(!highlighted(fence("", "#include <stdio.h>\nint main() { return 0; }")).contains("hljs-"))
    }

    @Test("markup inside code stays escaped", arguments: ["html", "swift", "js", "markdown", "nope"])
    func scriptStaysEscaped(language: String) {
        let html = highlighted(fence(language, "<script>alert(\"x\")</script><img src=x onerror=alert(1)>"))
        #expect(!html.contains("<script"))
        #expect(!html.contains("<img"))
        #expect(html.contains("&lt;"))
    }

    @Test("a block over the size cap is not highlighted")
    func oversizeBlock() {
        let stub = StubHighlighter { code, _ in code }
        let big = String(repeating: "x", count: CodeHighlighting.maximumBlockBytes + 1)
        let html = highlighted(fence("swift", big), highlighter: stub)
        #expect(stub.callCount == 0)
        #expect(html == "<pre><code class=\"language-swift\">\(big)\n</code></pre>\n")

        let real = highlighted(fence("swift", "let x = 1\n" + big))
        #expect(!real.contains("hljs-"))
    }

    @Test("highlighting stops once the per-document budget is used up")
    func documentBudget() {
        let stub = StubHighlighter { code, _ in "<span class=\"hljs-x\">\(code)</span>" }
        // 100 KB blocks (the literal includes the closing newline): two fit in 256 KB, a third
        // doesn't, but a later small block still does.
        let block = fence("swift", String(repeating: "y", count: 100 * 1024 - 1))
        let markdown = String(repeating: block + "\n", count: 3) + fence("swift", "small")
        let html = highlighted(markdown, highlighter: stub)
        #expect(stub.callCount == 3)
        #expect(html.components(separatedBy: "hljs-x").count - 1 == 3)
        #expect(html.contains("<span class=\"hljs-x\">small\n</span>"))

        // Tiny blocks are charged a minimum, which bounds the number of calls.
        let tiny = StubHighlighter { code, _ in code }
        _ = highlighted(String(repeating: fence("swift", "x") + "\n", count: 2000), highlighter: tiny)
        #expect(tiny.callCount == CodeHighlighting.documentBudgetBytes / CodeHighlighting.minimumChargeBytes)
    }

    @Test("rejected highlighter output falls back to plain escaped code")
    func rejectedOutput() {
        let stub = StubHighlighter { _, _ in "<span class=\"hljs-x\" onclick=\"alert(1)\">a</span>" }
        #expect(
            highlighted(fence("swift", "a"), highlighter: stub)
                == "<pre><code class=\"language-swift\">a\n</code></pre>\n")
        let lying = StubHighlighter { _, _ in "<span class=\"hljs-x\">b</span>" }
        #expect(
            highlighted(fence("swift", "a"), highlighter: lying)
                == "<pre><code class=\"language-swift\">a\n</code></pre>\n")
    }

    @Test("off without a highlighter, with the option off, and in spec mode")
    func disabled() {
        let plain = "<pre><code class=\"language-swift\">let x = 1\n</code></pre>\n"
        #expect(highlighted(fence("swift", "let x = 1"), highlighter: nil) == plain)
        var options = RenderOptions()
        options.highlighting = false
        #expect(HTMLRenderer(options: options).render(fence("swift", "let x = 1")).html == plain)
        #expect(HTMLRenderer(options: .spec).render(fence("swift", "let x = 1")).html == plain)
    }

    @Test("code blocks nested in containers are highlighted")
    func nested() {
        let html = highlighted(
            "> - item\n>\n>   ```swift\n>   let x = 1\n>   ```\n\n[^n]\n\n[^n]: note\n\n    ```js\n    var a\n    ```\n"
        )
        #expect(html.contains("<code class=\"language-swift\"><span class=\"hljs-keyword\">let</span>"))
        #expect(html.contains("<code class=\"language-js\"><span class=\"hljs-keyword\">var</span>"))
    }

    @Test("html(for:) highlights a parsed tree")
    func htmlForTree() {
        let tree = MarkdownParser(extensions: []).parse(fence("swift", "let x = 1"))
        #expect(HTMLRenderer().html(for: tree).contains("hljs-keyword"))
        let block = MarkdownNode(.codeBlock(CodeBlock(info: "swift", literal: "let x\n", isFenced: true)))
        #expect(HTMLRenderer().html(for: block).contains("hljs-keyword"))
    }

    @Test(
        "real highlight.js output passes validation for awkward input",
        arguments: [
            "swift", "js", "typescript", "python", "ruby", "go", "rust", "c", "cpp", "objectivec", "java", "kotlin",
            "csharp", "php", "html", "xml", "css", "scss", "json", "yaml", "toml", "ini", "sql", "bash", "shell",
            "diff", "markdown", "makefile", "graphql", "lua", "perl", "r", "cmake", "dart", "dockerfile", "elixir",
            "haskell", "nginx", "powershell", "scala",
        ]
    )
    func validatesRealOutput(language: String) throws {
        let code = """
            // "quotes" & 'apostrophes' <tags> </span> &amp; \\n \t tabs
            # comment ${x} `tick` @attr 0x1F 1.5e3 => -> :: #[derive] <?php ?> <!-- c -->
            emoji 🎉 café 日本語 \u{200B} \r\n line
            """
        let raw = try #require(HighlightJSHighlighter.shared.highlight(code, language: language))
        #expect(HighlightValidator.validated(raw, source: code) != nil)
    }

    @Test("concurrent rendering from many tasks is safe and deterministic")
    func concurrentRendering() async {
        let markdown = (0..<20).map { fence($0.isMultiple(of: 2) ? "swift" : "js", "let value\($0) = \"<\($0)>\"") }
            .joined(separator: "\n")
        let renderer = HTMLRenderer(highlighter: HighlightJSHighlighter())
        let expected = renderer.render(markdown).html
        #expect(expected.contains("hljs-"))
        let results = await withTaskGroup(of: String.self) { group in
            for _ in 0..<32 {
                group.addTask { renderer.render(markdown).html }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results.count == 32)
        #expect(results.allSatisfy { $0 == expected })
    }

    @Test("language names are passed as data and screened")
    func languageNames() {
        #expect(HighlightJSHighlighter.isPlausibleLanguageName("objective-c"))
        #expect(HighlightJSHighlighter.isPlausibleLanguageName("c++"))
        #expect(HighlightJSHighlighter.isPlausibleLanguageName("f#"))
        #expect(!HighlightJSHighlighter.isPlausibleLanguageName(""))
        #expect(!HighlightJSHighlighter.isPlausibleLanguageName("a\"b"))
        #expect(!HighlightJSHighlighter.isPlausibleLanguageName(String(repeating: "a", count: 33)))
        for name in ["__proto__", "constructor", "toString", "hasOwnProperty", "');alert(1);//"] {
            #expect(HighlightJSHighlighter.shared.highlight("x", language: name) == nil)
        }
    }

    @Test("a full HTML document stays self-contained, with no script")
    func selfContainedDocument() {
        let rendered = HTMLRenderer().render(fence("html", "<script src=\"https://x\"></script>"))
        let page = HTMLDocument(title: "t", body: rendered.html).html
        #expect(page.contains("hljs-"))
        #expect(!page.contains("<script"))
        #expect(DefaultTheme.css.contains(".hljs-keyword"))
    }
}

@Suite("HighlightValidator")
struct HighlightValidatorTests {
    private func validated(_ html: String, _ source: String) -> String? {
        HighlightValidator.validated(html, source: source)
    }

    @Test("accepts hljs spans and escaped text, re-escaping text like plain code")
    func accepts() {
        #expect(validated("", "")?.isEmpty == true)
        #expect(validated("a &amp; b", "a & b") == "a &amp; b")
        #expect(
            validated("<span class=\"hljs-string\">&quot;&#x27;&#39;&lt;&gt;</span>", "\"''<>")
                == "<span class=\"hljs-string\">&quot;''&lt;&gt;</span>"
        )
        let scopes =
            "<span class=\"hljs-title function_\">f</span>"
            + "<span class=\"language-xml\"><span class=\"hljs-tag\">x</span></span>"
        #expect(validated(scopes, "fx") == scopes)
        #expect(validated("caf\u{E9} 🎉\n", "caf\u{E9} 🎉\n") == "caf\u{E9} 🎉\n")
    }

    @Test(
        "rejects anything else",
        arguments: [
            "<script>x</script>",
            "<span>x</span>",
            "<span class=\"x\">x</span>",
            "<span class=\"hljs-\"x>x</span>",
            "<span class=\"HLJS-X\">x</span>",
            "<span class=\"hljs-a\" onclick=\"x\">x</span>",
            "<span class='hljs-a'>x</span>",
            "<span  class=\"hljs-a\">x</span>",
            "<span class=\"hljs-a:b\">x</span>",
            "<span class=\"hljs-a&quot;\">x</span>",
            "<span class=\"hljs-a\">x",
            "x</span>",
            "<span class=\"hljs-a\">x</span >",
            "<SPAN class=\"hljs-a\">x</SPAN>",
            "<span class=\"hljs-a\">x</span></span>",
            "<b>x</b>",
            "<!-- -->x",
            "x>",
            "\"x",
            "'x",
            "&nbsp;x",
            "&#60;x",
            "&amp",
            "<",
        ]
    )
    func rejects(_ html: String) {
        #expect(validated(html, "x") == nil)
    }

    @Test("rejects output whose text differs from the source")
    func textMismatch() {
        #expect(validated("<span class=\"hljs-a\">x</span>", "y") == nil)
        #expect(validated("x", "x\n") == nil)
        #expect(validated("x\n", "x") == nil)
    }

    @Test("limits class length and nesting depth")
    func limits() {
        let longClass = "hljs-" + String(repeating: "a", count: HighlightValidator.maximumClassLength)
        #expect(validated("<span class=\"\(longClass)\">x</span>", "x") == nil)
        let deep = HighlightValidator.maximumDepth
        let nested =
            String(repeating: "<span class=\"hljs-a\">", count: deep) + "x" + String(repeating: "</span>", count: deep)
        #expect(validated(nested, "x") != nil)
        let tooDeep = "<span class=\"hljs-a\">" + nested + "</span>"
        #expect(validated(tooDeep, "x") == nil)
    }
}
