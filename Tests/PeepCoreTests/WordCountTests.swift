import Foundation
import Testing

@testable import PeepCore

@Suite("Word count")
struct WordCountTests {
    static func count(_ markdown: String, options: RenderOptions = RenderOptions()) -> Int {
        HTMLRenderer(options: options).render(markdown).wordCount
    }

    @Test(
        "Counts the words a reader sees",
        arguments: [
            ("", 0),
            ("   \n\n", 0),
            ("One two three.", 3),
            ("Hello, world! It's 2026.", 4),
            // Markup joins as written; punctuation and rules are not words.
            ("**foo**bar and *baz*", 3),
            ("a ~~b~~ c\n\n---\n\nd", 4),
            // Line breaks and blocks separate words.
            ("one\ntwo", 2),
            ("one  \ntwo", 2),
            ("# Title\nBody text", 3),
            ("> quoted words\n\n- item one\n- item two", 6),
            ("- [x] done task\n- [ ] open task", 4),
            // Link labels count, destinations don't; autolinks show their URL.
            ("[read the docs](https://example.com/some/long/path)", 3),
            // Images and raw HTML aren't words.
            ("before ![alt text here](x.png) after", 2),
            ("before <span title=\"a b c\">inside</span> after", 3),
            ("<div>\nraw block words\n</div>\n\nvisible", 1),
            // Code is visible text.
            ("run `swift test` now", 4),
            ("```swift\nlet x = 1\nprint(x)\n```", 5),
            // Tables: each cell is separate.
            ("| a | b |\n|---|---|\n| c | d |", 4),
            // Footnotes: the definition's words count, the reference number doesn't.
            ("Claim[^1].\n\n[^1]: The source.", 3),
            // Emoji aren't words.
            ("ship :tada: it", 2),
            ("ship it :tada::rocket:", 2),
        ])
    func counts(markdown: String, expected: Int) {
        #expect(Self.count(markdown) == expected, "\(markdown.debugDescription)")
    }

    @Test("Scripts without spaces are segmented")
    func unspacedScripts() {
        // ICU's segmentation decides the exact count; a whole sentence is more than one word.
        #expect(Self.count("日本語の文章です") > 1)
        #expect(Self.count("我们今天去公园散步") > 1)
    }

    @Test("Frontmatter is not counted")
    func frontmatter() {
        let markdown = "---\ntitle: A long frontmatter title\ntags: [one, two]\n---\nJust three words"
        #expect(Self.count(markdown) == 3)
        var options = RenderOptions()
        options.frontmatterDisplay = .table
        #expect(Self.count(markdown, options: options) == 3)
    }

    @Test("Alert titles are the renderer's, not the document's")
    func alerts() {
        #expect(Self.count("> [!NOTE]\n> Read this first.") == 3)
    }

    @Test("Wiki links count their label")
    func wikiLinks() {
        var options = RenderOptions()
        options.builtInPreprocessors = [.wikiLinks]
        let rendered = HTMLRenderer(options: options, wikiLinkResolver: FakeWikiLinkResolver(["Home.md"]))
            .render("See [[Home|the home page]] and [[Missing]].")
        #expect(rendered.wordCount == 6)
    }

    @Test("Spec mode counts the same text")
    func specMode() {
        #expect(Self.count("**foo**bar and *baz*", options: .spec) == 3)
    }
}
