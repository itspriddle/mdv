import Testing

@testable import MdvCore

// How the expected slugs were verified (2026-11-06): each heading was rendered by GitHub with
//
//     gh api markdown -f mode=markdown -f text="$(cat headings.md)"
//
// and the `id` read off the `<a class="anchor">` GitHub emits after each heading. GitHub prefixes
// every id with `user-content-` (and links with the bare slug, `href="#slug"`); the expectations
// below drop that prefix. `mode=gfm` does not emit heading ids, so `mode=markdown` was used; both
// use the same parser and slug filter.

/// The markup `HTMLRenderer` writes for a heading with anchors on.
func anchoredHeading(_ level: Int, _ slug: String, _ content: String) -> String {
    "<h\(level) id=\"\(slug)\"><a class=\"anchor\" aria-hidden=\"true\" href=\"#\(slug)\"></a>\(content)</h\(level)>"
}

private let allExtensions = RenderOptions(extensions: Set(MarkdownExtension.allCases))

private func headings(_ markdown: String, options: RenderOptions = allExtensions) -> [Heading] {
    HTMLRenderer(options: options).render(markdown).headings
}

private func slugs(_ markdown: String) -> [String] {
    headings(markdown).map(\.slug)
}

@Suite("Heading slugs: GitHub-verified")
struct HeadingSlugTests {
    @Test(
        "single heading → GitHub slug",
        arguments: [
            // ASCII basics and punctuation
            ("# Hello World", "hello-world"),
            ("# Mixed CASE Text", "mixed-case-text"),
            ("# What's new?", "whats-new"),
            ("# C++ & C#", "c--c"),
            ("# foo_bar-baz", "foo_bar-baz"),
            ("# snake_case_name", "snake_case_name"),
            ("# Hyphen-ated-Word", "hyphen-ated-word"),
            ("# ---dashes---", "---dashes---"),
            ("# Trailing dash -", "trailing-dash--"),
            ("# Multiple   spaces   here", "multiple---spaces---here"),
            ("# Version 1.2.3", "version-123"),
            ("# 3.14159", "314159"),
            ("# 100% done!", "100-done"),
            ("# 1. Numbered", "1-numbered"),
            ("# a.b/c\\d", "abcd"),
            ("# &amp; entity &copy; ©", "-entity--"),
            ("# one—two – three", "onetwo--three"),
            ("# don’t “smart” quotes", "dont-smart-quotes"),
            // Only ASCII space becomes `-`; other whitespace is dropped
            ("# Tab\tseparated", "tabseparated"),
            ("# non\u{A0}breaking", "nonbreaking"),
            ("# zero\u{200B}width", "zerowidth"),
            // Inline markup: text and code spans count, raw HTML tags and image alt do not
            ("### `code span` heading", "code-span-heading"),
            ("# `a b`  `c`", "a-b--c"),
            ("# *Emphasis* and **strong**", "emphasis-and-strong"),
            ("# [Link text](https://example.com)", "link-text"),
            ("# See https://example.com now", "see-httpsexamplecom-now"),
            ("# ~~strike~~ text", "strike-text"),
            ("# <span>html</span> inline", "html-inline"),
            ("# <code>raw</code> html code", "raw-html-code"),
            ("# Foo <!-- comment --> bar", "foo--bar"),
            ("# ![alt text](img.png) image", "-image"),
            ("# Title[^1]\n\n[^1]: note", "title1"),
            ("Setext line one\nline two\n===", "setext-line-oneline-two"),
            ("Hard\\\nbreak\n---", "hardbreak"),
            // Unicode letters, marks, and numbers
            ("# Ünïcödé Héading", "ünïcödé-héading"),
            ("# Café au lait", "café-au-lait"),
            ("# ÆØÅ uppercase", "æøå-uppercase"),
            ("# Straße", "straße"),
            ("# İstanbul", "i\u{307}stanbul"),
            ("# ΟΔΟΣ", "οδοσ"),
            ("# Ελληνικά", "ελληνικά"),
            ("# Привет мир", "привет-мир"),
            ("# 日本語の見出し", "日本語の見出し"),
            ("# Arabic عربي", "arabic-عربي"),
            ("# Hindi हिन्दी", "hindi-हिन्दी"),
            ("# Ǆ title case", "ǆ-title-case"),
            ("# Ⅷ roman numeral", "ⅷ-roman-numeral"),
            ("# Ⓐ circled", "ⓐ-circled"),
            ("# x²", "x"),
            ("# ½ half", "-half"),
            // Emoji are dropped, but variation selectors (marks) and ZWJ (join control) stay
            ("# Emoji 🎉 party", "emoji--party"),
            ("# x 🎉", "x-"),
            ("# 👍🏽 Thumbs", "-thumbs"),
            ("# 🇺🇸 flag", "-flag"),
            ("# ❤️ Love", "\u{FE0F}-love"),
            ("# 👨‍👩‍👧 family", "\u{200D}\u{200D}-family"),
            // GitHub slugs a shortcode's name, not its emoji (see #10)
            ("# :tada: shortcode", "tada-shortcode"),
        ]
    )
    func slug(markdown: String, expected: String) {
        #expect(slugs(markdown) == [expected])
    }

    @Test("duplicates get the first free -N suffix in document order")
    func duplicates() {
        #expect(
            slugs("# Hello World\n## Hello World\n## Hello World\n# Hello World-1")
                == ["hello-world", "hello-world-1", "hello-world-2", "hello-world-1-1"])
        #expect(slugs("# A\n# A-1\n# A\n# A") == ["a", "a-1", "a-2", "a-3"])
        #expect(slugs("# B-1\n# B\n# B") == ["b-1", "b", "b-2"])
    }

    @Test("empty slugs still get unique ids (GitHub: \"\", -1, -2, ...)")
    func emptySlugs() {
        // GitHub gives the first empty slug `id=""` and later ones `-1`, `-2`; mdv uses `-0` first.
        #expect(slugs("# ???\n# !!!") == ["-0", "-1"])
        #expect(slugs("#\n#\n# 🎉") == ["-0", "-1", "-2"])
        #expect(slugs("# -0\n#") == ["-0", "-1"])
    }
}

@Suite("Heading anchors: rendering")
struct HeadingAnchorRenderingTests {
    @Test("headings get an id and an empty anchor link")
    func markup() {
        let html = HTMLRenderer().render("## Hello *World*").html
        #expect(
            html
                == "<h2 id=\"hello-world\"><a class=\"anchor\" aria-hidden=\"true\" href=\"#hello-world\"></a>"
                + "Hello <em>World</em></h2>\n")
    }

    @Test("an empty heading gets a unique id")
    func emptyHeading() {
        let html = HTMLRenderer().render("#\n#").html
        #expect(html.contains("<h1 id=\"-0\">"))
        #expect(html.contains("<h1 id=\"-1\">"))
    }

    @Test("Unicode slugs are written verbatim")
    func unicode() {
        #expect(
            HTMLRenderer().render("# Café").html.hasPrefix(
                "<h1 id=\"café\"><a class=\"anchor\" aria-hidden=\"true\" href=\"#café\">"))
    }

    @Test("anchors off: plain headings, but headings and title are still filled in")
    func disabled() {
        var options = RenderOptions()
        options.headingAnchors = false
        let rendered = HTMLRenderer(options: options).render("# One\n## One")
        #expect(rendered.html == "<h1>One</h1>\n<h2>One</h2>\n")
        #expect(rendered.headings.map(\.slug) == ["one", "one-1"])
        #expect(rendered.title == "One")
    }

    @Test("spec mode turns anchors off")
    func specMode() {
        #expect(!RenderOptions.spec.headingAnchors)
        #expect(HTMLRenderer(options: .spec).render("# One").html == "<h1>One</h1>\n")
    }

    @Test("a pre-parsed tree gets anchors too")
    func tree() {
        let tree = MarkdownNode(
            .document, children: [MarkdownNode(.heading(level: 3), children: [MarkdownNode(.text("Hi"))])])
        #expect(HTMLRenderer().html(for: tree).hasPrefix("<h3 id=\"hi\">"))
    }
}

@Suite("Heading anchors: headings and title")
struct HeadingListTests {
    @Test("headings list level, plain text, slug, and source line in document order")
    func list() {
        let markdown = "# Intro\n\ntext\n\n> ## Quoted `code`\n\n- ### In *list*\n\nSetext\n---\n"
        #expect(
            headings(markdown) == [
                Heading(level: 1, text: "Intro", slug: "intro", sourceLine: 1),
                Heading(level: 2, text: "Quoted code", slug: "quoted-code", sourceLine: 5),
                Heading(level: 3, text: "In list", slug: "in-list", sourceLine: 7),
                Heading(level: 2, text: "Setext", slug: "setext", sourceLine: 9),
            ])
    }

    @Test("text drops raw HTML and image alt, turns breaks into spaces, and is trimmed")
    func text() {
        #expect(headings("# ![logo](x.png) Name <b>bold</b>").map(\.text) == ["Name bold"])
        #expect(headings("Line one\nline two\n===").map(\.text) == ["Line one line two"])
        #expect(headings("# Title[^1]\n\n[^1]: note").map(\.text) == ["Title"])
    }

    @Test("source lines are lines in the original file, after frontmatter")
    func sourceLineAfterFrontmatter() {
        #expect(headings("---\ntitle: T\n---\n\n# One\n").map(\.sourceLine) == [5])
    }

    @Test("title: frontmatter wins, then the first non-empty h1")
    func title() {
        func title(_ markdown: String) -> String? {
            HTMLRenderer().render(markdown).title
        }
        #expect(title("---\ntitle: Front\n---\n# Heading\n") == "Front")
        #expect(title("## Two\n# One *em*\n# Later") == "One em")
        #expect(title("#\n# Real") == "Real")
        #expect(title("## Only h2") == nil)
        #expect(title("no headings") == nil)
    }
}
