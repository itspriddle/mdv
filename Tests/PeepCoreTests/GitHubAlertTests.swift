import Foundation
import Testing

@testable import MdvCore

private func html(_ markdown: String, options: RenderOptions = RenderOptions()) -> String {
    HTMLRenderer(options: options).render(markdown).html
}

private func isAlert(_ markdown: String, options: RenderOptions = RenderOptions()) -> Bool {
    html(markdown, options: options).contains("class=\"markdown-alert ")
}

/// GitHub alerts (#52). github.com's rules are checked against its own rendering in
/// `GitHubFixtureTests` (`Fixtures/github/alerts.md`) and recorded in `Fixtures/flavors`; these
/// cover what those can't show: the tree, source lines, the outline, escaping, and options.
@Suite("GitHub alerts")
struct GitHubAlertTests {
    @Test("each type has GitHub's class, title, and Octicon", arguments: GitHubAlert.allCases)
    func markup(type: GitHubAlert) {
        let output = html("> [!\(type.rawValue.uppercased())]\n> Body.\n")
        #expect(
            output
                == "<div class=\"markdown-alert markdown-alert-\(type.rawValue)\"><p class=\"markdown-alert-title\">"
                + "\(type.iconSVG)\(type.title)</p>\n<p>Body.</p>\n</div>\n")
        #expect(type.iconSVG.contains("octicon-\(type.octiconName)"))
    }

    @Test("the tree: an alert node holding the body, the marker line removed")
    func tree() throws {
        let root = MarkdownParser().parse("> [!tip]\n> Body *text*.\n>\n> More.\n")
        let alert = try #require(GitHubAlerts.alert(from: root.children[0], options: RenderOptions()))
        #expect(alert.kind == .alert(.tip))
        #expect(alert.children.map(\.kind) == [.paragraph, .paragraph])
        #expect(alert.children[0].children.first?.kind == .text("Body "))
    }

    @Test(
        "edge cases github.com renders as block quotes",
        arguments: [
            "> [!NOTE]\n", "> [!NOTE] text\n> body\n", "> [!NOTE]\n> <!-- comment -->\n",
            "> [!NOTE]\n> <script>x</script>\n",
            "> [!NOTE]<br>\n", "> # [!NOTE]\n> body\n", "> [!NOTE]\n> ---\n", "> [!NOTE]\u{A0}\n> body\n",
            "> [!NÖTE]\n> body\n", "> [!]\n> body\n", "- > [!NOTE]\n  > body\n", "> > [!NOTE]\n> > body\n",
            "> [!note]\n> body\n\n[!note]: https://example.com\n",
        ])
    func notAlerts(markdown: String) {
        #expect(!isAlert(markdown))
    }

    @Test("CRLF and CR line endings work like LF")
    func lineEndings() {
        #expect(isAlert("> [!NOTE]\r\n> body\r\n"))
        #expect(isAlert("> [!NOTE]\r> body\r"))
    }

    @Test("raw HTML after the marker counts as a body when it leaves an element")
    func rawHTMLBody() {
        #expect(isAlert("> [!NOTE]\n> <div>x</div>\n"))
        // Without sanitizing, the script is kept, so it's a body; a comment never is.
        var unsanitized = RenderOptions()
        unsanitized.sanitize = false
        #expect(isAlert("> [!NOTE]\n> <script>x</script>\n", options: unsanitized))
        #expect(!isAlert("> [!NOTE]\n> <!-- comment -->\n", options: unsanitized))
    }

    @Test("the alert carries the block quote's source line; the body keeps its own")
    func sourceLines() {
        var options = RenderOptions()
        options.sourceLines = true
        let output = html("Intro.\n\n> [!NOTE]\n> Body.\n>\n> - item\n\n> [!TIP]\n>\n> Para.\n", options: options)
        #expect(output.contains("<div class=\"markdown-alert markdown-alert-note\" data-source-line=\"3\">"))
        #expect(output.contains("<p data-source-line=\"4\">Body.</p>"))
        #expect(output.contains("<ul data-source-line=\"6\">"))
        #expect(output.contains("<div class=\"markdown-alert markdown-alert-tip\" data-source-line=\"8\">"))
        #expect(output.contains("<p data-source-line=\"10\">Para.</p>"))
        // The title is renderer output, not a source block.
        #expect(output.contains("<p class=\"markdown-alert-title\"><svg"))
        let lines = output.matches(of: /data-source-line="(\d+)"/).compactMap { Int($0.1) }
        #expect(lines == lines.sorted())
    }

    @Test("titles aren't headings: the outline has only the document's own headings")
    func outline() {
        let rendered = HTMLRenderer().render("# Doc\n\n> [!WARNING]\n> ## Inside\n> Text.\n")
        #expect(rendered.headings.map(\.text) == ["Doc", "Inside"])
    }

    @Test("emoji shortcodes in the body convert; alerts run first")
    func emojiInBody() {
        #expect(MarkdownTransform.allCases.first == .alerts)
        #expect(html("> [!TIP]\n> :tada: done\n").contains("<p>🎉 done</p>"))
    }

    @Test("body text is escaped like any paragraph")
    func escaping() {
        #expect(html("> [!NOTE]\n> <b onclick=x>&\n").contains("<p><b>&amp;</b></p>"))
    }

    @Test("off in CommonMark and spec mode, on as a built-in preprocessor")
    func flavors() {
        #expect(!isAlert("> [!NOTE]\n> body\n", options: RenderOptions(flavor: .commonmark)))
        #expect(HTMLRenderer(options: .spec).render("> [!NOTE]\n> body\n").html.hasPrefix("<blockquote>"))
        var options = RenderOptions(flavor: .commonmark)
        options.builtInPreprocessors = [.alerts]
        #expect(isAlert("> [!NOTE]\n> body\n", options: options))
    }
}
