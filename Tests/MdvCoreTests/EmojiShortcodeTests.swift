import Foundation
import Testing

@testable import MdvCore

// Expected output was verified (2026-11-06) by rendering each input with
//
//     gh api markdown -f mode=gfm -f text="$(cat input.md)"
//
// github.com wraps some emoji in `<g-emoji>`; mdv writes the bare character. Heading slugs were
// checked with `mode=markdown`, which emits heading ids. `Fixtures/github/emoji.md` covers more.

/// The inner HTML of a one-paragraph document, rendered with default options.
private func paragraph(_ markdown: String, options: RenderOptions = RenderOptions()) -> String {
    var options = options
    options.headingAnchors = false
    let html = HTMLRenderer(options: options).render(markdown).html
    return String(html.trimmingCharacters(in: .newlines).dropFirst("<p>".count).dropLast("</p>".count))
}

@Suite("Emoji shortcodes")
struct EmojiShortcodeTests {
    @Test(
        "GitHub-verified conversions",
        arguments: [
            (":tada:", "🎉"),
            ("thanks :+1: not :-1:", "thanks 👍 not 👎"),
            (":white_check_mark: :1st_place_medal: :100: :1234: :t-rex: :e-mail:", "✅ 🥇 💯 🔢 🦖 📧"),
            (":smile_cat:", "😸"),
            // Adjacent shortcodes, and leftovers after a match.
            (":a::b::ab:", "🅰️🅱️🆎"),
            (":tada::tada:", "🎉🎉"),
            (":tada:tada:", "🎉tada:"),
            (":+1::", "👍:"),
            (":nope:tada:", ":nope🎉"),
            ("x :x:tada:", "x ❌tada:"),
            // Colons alone.
            ("::", "::"),
            (":::", ":::"),
            (":: :tada:", ":: 🎉"),
            // Unknown, mis-cased, and malformed aliases stay literal.
            (":nope:", ":nope:"),
            (":TADA:", ":TADA:"),
            (":ta da:", ":ta da:"),
            (":tada", ":tada"),
            // GitHub's image-only emoji have no character; mdv never loads remote images.
            (":octocat: :shipit:", ":octocat: :shipit:"),
            // Text is matched after cmark resolves escapes and entities.
            (#"\:tada:"#, "🎉"),
            ("&#58;tada:", "🎉"),
            // A combining mark after the closing colon stays with the following text.
            (":tada:\u{301}x", "🎉\u{301}x"),
            ("**:tada:** *x*:tada: ~~:tada:~~", "<strong>🎉</strong> <em>x</em>🎉 <del>🎉</del>"),
        ])
    func converts(_ markdown: String, _ expected: String) {
        #expect(paragraph(markdown) == expected)
    }

    @Test(
        "the first candidate in a text run decides, as on github.com",
        arguments: [
            ("x:tada:", "x:tada:"),
            ("(:tada:)", "(:tada:)"),
            ("/:tada:/", "/:tada:/"),
            ("1:tada:", "1:tada:"),
            (":::tada:", ":::tada:"),
            ("x::tada:", "x::tada:"),
            ("x\t:tada:", "x\t:tada:"),
            ("x\u{A0}:tada:", "x\u{A0}:tada:"),
            ("x x:tada: :tada:", "x x:tada: :tada:"),
            ("a :tada: then x:tada: (:tada:) /:tada:/", "a 🎉 then x🎉 (🎉) /🎉/"),
            ("a. :tada:", "a. 🎉"),
            ("x/y :tada:", "x/y 🎉"),
            ("*a* b:tada:", "<em>a</em> b:tada:"),
        ])
    func boundaries(_ markdown: String, _ expected: String) {
        #expect(paragraph(markdown) == expected)
    }

    @Test("code spans, code blocks, raw HTML, and image alt text are untouched")
    func untouched() {
        #expect(paragraph("`:tada:` :tada:") == "<code>:tada:</code> 🎉")
        #expect(HTMLRenderer().render("    :tada:\n").html == "<pre><code>:tada:\n</code></pre>\n")
        #expect(HTMLRenderer().render("```\n:tada:\n```\n").html == "<pre><code>:tada:\n</code></pre>\n")
        #expect(paragraph(#"<span title=":tada:">:tada:</span>"#) == #"<span title=":tada:">🎉</span>"#)
        #expect(paragraph("![:tada: alt](x.png)") == #"<img src="x.png" alt=":tada: alt" />"#)
    }

    @Test("link text converts; destinations and autolinked URLs do not")
    func links() {
        #expect(
            paragraph("[:tada: link](https://example.com/:tada:/)")
                == #"<a href="https://example.com/:tada:/">🎉 link</a>"#)
        #expect(paragraph("[x:tada:](y)") == #"<a href="y">x:tada:</a>"#)
        #expect(
            paragraph("[ref :tada:][r]\n\n[r]: https://example.com/:tada:")
                == #"<a href="https://example.com/:tada:">ref 🎉</a>"#)
        #expect(
            paragraph("https://example.com/:tada:/ :tada:")
                == #"<a href="https://example.com/:tada:/">https://example.com/:tada:/</a> 🎉"#)
        #expect(paragraph("<https://x.co/:tada:>") == #"<a href="https://x.co/:tada:">https://x.co/:tada:</a>"#)
        #expect(paragraph("www.x.co/a:tada:/b") == #"<a href="http://www.x.co/a:tada:/b">www.x.co/a:tada:/b</a>"#)
    }

    @Test("an autolink's text is never converted, even where a shortcode could start")
    func autolinkText() {
        let link = MarkdownNode(
            .link(destination: ":tada:", title: nil), children: [MarkdownNode(.text(":tada:"))])
        let root = MarkdownNode(.document, children: [MarkdownNode(.paragraph, children: [link])])
        #expect(EmojiShortcodes.replace(in: root) == root)
    }

    @Test("adjacent text nodes are matched as one run")
    func splitText() throws {
        // cmark consolidates its text nodes; a tree built another way may not be.
        func text(_ literal: String, column: Int) -> MarkdownNode {
            let end = column + literal.utf8.count - 1
            return MarkdownNode(
                .text(literal),
                sourceRange: SourceRange(
                    start: SourcePosition(line: 1, column: column), end: SourcePosition(line: 1, column: end)))
        }
        let split = MarkdownNode(
            .paragraph,
            children: [text("a :white", column: 1), text("_check", column: 9), text("_mark: b", column: 15)])
        let replaced = EmojiShortcodes.replace(in: MarkdownNode(.document, children: [split]))
        let paragraph = try #require(replaced.children.first)
        #expect(
            paragraph.children.map(\.kind) == [
                .text("a "), .emoji(shortcode: "white_check_mark", character: "✅"), .text(" b"),
            ])
        let run = SourceRange(start: SourcePosition(line: 1, column: 1), end: SourcePosition(line: 1, column: 22))
        #expect(paragraph.children.allSatisfy { $0.sourceRange == run })
    }

    @Test("emoji in tables and task lists")
    func blocks() {
        let html = HTMLRenderer().render("- [ ] :construction: todo\n\n| :tada: |\n| --- |\n| :smile: |\n").html
        #expect(html.contains("> 🚧 todo</li>"))
        #expect(html.contains("<th>🎉</th>"))
        #expect(html.contains("<td>😄</td>"))
    }

    @Test("GFM only: off in CommonMark and spec mode")
    func disabled() {
        #expect(paragraph(":tada:", options: RenderOptions(flavor: .commonmark)) == ":tada:")
        #expect(HTMLRenderer(options: .spec).render(":tada:").html == "<p>:tada:</p>\n")
        #expect(RenderOptions().transforms.contains(.emojiShortcodes))
    }

    @Test("emoji characters are written escaped")
    func escaped() {
        let root = MarkdownNode(
            .paragraph, children: [MarkdownNode(.emoji(shortcode: "x", character: "<b>&"))])
        #expect(HTMLRenderer().html(for: root) == "<p>&lt;b&gt;&amp;</p>\n")
    }

    @Test("content dropped by the sanitizer drops its emoji too")
    func sanitized() {
        #expect(paragraph("a <script>:tada:</script> :tada:") == "a  🎉")
    }
}

@Suite("Emoji shortcodes in headings")
struct EmojiHeadingTests {
    @Test(
        "heading text shows the emoji; the slug uses the shortcode (GitHub-verified)",
        arguments: [
            ("# :tada: Release", "🎉 Release", "tada-release"),
            ("## :+1: and :octocat: and :nope:", "👍 and :octocat: and :nope:", "1-and-octocat-and-nope"),
            ("## Emoji 🎉 party :tada:", "Emoji 🎉 party 🎉", "emoji--party-tada"),
        ])
    func heading(_ markdown: String, _ text: String, _ slug: String) throws {
        let document = HTMLRenderer().render(markdown)
        let heading = try #require(document.headings.first)
        #expect(heading.text == text)
        #expect(heading.slug == slug)
    }

    @Test("the document title uses the emoji")
    func title() {
        #expect(HTMLRenderer().render("# :tada: Release\n").title == "🎉 Release")
    }

    @Test("slugs are the same with emoji off")
    func slugWithoutEmoji() {
        let document = HTMLRenderer(options: RenderOptions(flavor: .commonmark)).render("# :tada: Release\n")
        #expect(document.headings.map(\.slug) == ["tada-release"])
        #expect(document.title == ":tada: Release")
    }
}

@Suite("Emoji table")
struct EmojiTableTests {
    @Test("covers gemoji's Unicode emoji and no image-only emoji")
    func contents() {
        #expect(EmojiShortcodes.table.count > 1800)
        #expect(EmojiShortcodes.table["tada"] == "🎉")
        #expect(EmojiShortcodes.table["+1"] == "👍")
        #expect(EmojiShortcodes.table["octocat"] == nil)
        #expect(
            EmojiShortcodes.table.keys.allSatisfy {
                $0.allSatisfy { "abcdefghijklmnopqrstuvwxyz0123456789_+-".contains($0) }
            })
    }

    @Test("generated file is sorted by alias, one entry per line")
    func generatedFileIsSorted() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/MdvCore/Generated/EmojiTable.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let aliases = source.split(separator: "\n").compactMap { line in
            line.firstMatch(of: /^ {8}"([^"]+)": "/).map { String($0.1) }
        }
        #expect(aliases.count == EmojiShortcodes.table.count)
        #expect(aliases == aliases.sorted())
        #expect(source.contains("github/gemoji/blob/"))
    }
}
