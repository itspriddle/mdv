import Foundation
import Testing

@testable import MdvCore

/// Compares default-mode output with GitHub's rendering of the same Markdown
/// (`Fixtures/github`, captured with `gh api markdown`). See that folder's README.
@Suite("GitHub reference fixtures")
struct GitHubFixtureTests {
    static let fixtures = ["tables", "strikethrough-autolinks", "task-lists"]

    @Test("default output matches GitHub", arguments: fixtures)
    func matchesGitHub(_ name: String) throws {
        let markdown = try Self.fixture(name, "md")
        let expected = Self.strippingGitHubSiteMarkup(try Self.fixture(name, "html"))
        let actual = HTMLRenderer().render(markdown).html
        #expect(actual.trimmingCharacters(in: .whitespacesAndNewlines) == expected)
    }

    /// Removes what github.com layers on top of its Markdown rendering (see the README).
    static func strippingGitHubSiteMarkup(_ html: String) -> String {
        var html = html
        for literal in [
            "<markdown-accessiblity-table>", "</markdown-accessiblity-table>", " role=\"table\"",
            " rel=\"nofollow\"", " class=\"notranslate\"", " id=\"\"", "user-content-",
        ] {
            html = html.replacingOccurrences(of: literal, with: "")
        }
        html = html.replacing(/-[0-9a-f]{32}(?=")/, with: "")
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
