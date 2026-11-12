import Foundation
import Testing

@testable import PeepCore

/// Compares default-mode output with GitHub's rendering of the same Markdown
/// (`Fixtures/github`, captured with `gh api markdown`). See that folder's README.
@Suite("GitHub reference fixtures")
struct GitHubFixtureTests {
    static let fixtures = ["tables", "strikethrough-autolinks", "task-lists", "footnotes", "emoji"]

    @Test("default output matches GitHub", arguments: fixtures)
    func matchesGitHub(_ name: String) throws {
        let markdown = try Self.fixture(name, "md")
        let expected = Self.strippingGitHubSiteMarkup(try Self.fixture(name, "html"))
        let actual = HTMLRenderer().render(markdown).html
        #expect(actual.trimmingCharacters(in: .whitespacesAndNewlines) == expected)
    }

    /// GitHub alerts (#52): every rule `GitHubAlerts` documents, as GitHub's API renders it. The
    /// fixture needs line breaks (the marker is alone on its line), which `mode=gfm` writes as
    /// `<br>`, so GitHub's soft breaks become newlines here (the fixture has no hard breaks
    /// outside markers), and both sides are normalized: Peep starts each body block on a new line
    /// where GitHub doesn't.
    @Test("alerts match GitHub, and so do their Octicons, byte for byte")
    func alertsMatchGitHub() throws {
        let markdown = try Self.fixture("alerts", "md")
        let github = try Self.fixture("alerts", "html")
        let expected = Self.strippingGitHubSiteMarkup(github).replacingOccurrences(of: "<br>\n", with: "\n")
        let actual = HTMLRenderer().render(markdown).html
        #expect(HTMLNormalizer.normalize(actual) == HTMLNormalizer.normalize(expected))
        for type in GitHubAlert.allCases {
            #expect(github.contains("\(type.iconSVG)\(type.title)</p>"), "\(type)")
        }
    }

    /// Removes what github.com layers on top of its Markdown rendering (see the README).
    static func strippingGitHubSiteMarkup(_ html: String) -> String {
        var html = html
        for literal in [
            "<markdown-accessiblity-table>", "</markdown-accessiblity-table>", " role=\"table\"",
            " rel=\"nofollow\"", " class=\"notranslate\"", " id=\"\"", "user-content-", "</g-emoji>",
        ] {
            html = html.replacingOccurrences(of: literal, with: "")
        }
        html = html.replacing(/-[0-9a-f]{32}(?=")/, with: "")
        html = html.replacing(/<g-emoji class="g-emoji" alias="[^"]*">/, with: "")
        return html.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fixture(_ name: String, _ ext: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures/github")
        else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
