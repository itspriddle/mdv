import Foundation
import Testing

@testable import PeepCore

/// The README corpus (`Fixtures/corpus`, see its README): real documents rendered by Peep with
/// default options, compared with GitHub's rendering after normalization, and snapshotted.
///
/// Re-record the snapshots after an intended output change:
///
///     PEEP_RECORD_SNAPSHOTS=1 swift test --filter GitHubCorpusTests
///
/// To inspect a GitHub mismatch, `PEEP_CORPUS_DIFF_DIR=/some/dir` writes both normalized outputs
/// there as `NAME.github.html` and `NAME.peep.html`; compare them one tag per line, e.g.
/// `diff <(sed 's/></>\n</g' NAME.github.html) <(sed 's/></>\n</g' NAME.peep.html)`.
@Suite("GitHub README corpus")
struct GitHubCorpusTests {
    static let manifest: CorpusManifest = {
        do {
            return try JSONDecoder().decode(CorpusManifest.self, from: Data(contentsOf: try fixtureURL("corpus.json")))
        } catch {
            preconditionFailure("unreadable Fixtures/corpus/corpus.json: \(error)")
        }
    }()

    static let names = manifest.documents.keys.sorted()

    @Test("every corpus file is in the manifest with its source, commit, and license")
    func manifestIsComplete() throws {
        let directory = try Self.fixtureURL("corpus.json").deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let markdown = Set(files.filter { $0.hasSuffix(".md") && $0 != "README.md" }.map { String($0.dropLast(3)) })
        #expect(markdown == Set(Self.names))
        #expect((10...15).contains(Self.names.count))
        for (name, document) in Self.manifest.documents {
            #expect(
                document.source.hasPrefix("https://github.com/") && document.source.contains(document.commit), "\(name)"
            )
            #expect(document.commit.wholeMatch(of: /[0-9a-f]{40}/) != nil, "\(name)")
            #expect(Self.permissiveLicenses.contains(document.license), "\(name): \(document.license)")
            for exception in document.exceptions {
                #expect(exception.reason.count > 10, "\(name): every exception needs a reason")
            }
        }
    }

    @Test("matches GitHub's rendering, apart from documented exceptions", arguments: names)
    func matchesGitHub(_ name: String) throws {
        let markdown = try Self.fixture(name, "md")
        let hasFrontmatter = Frontmatter.extract(from: markdown)?.frontmatter.format == .yaml
        var expected = CorpusNormalizer.github(try Self.fixture(name, "github.html"), hasFrontmatter: hasFrontmatter)
        for exception in Self.manifest.documents[name]?.exceptions ?? [] {
            #expect(
                expected.ranges(of: exception.github).count == 1,
                "\(name): exception must match GitHub's normalized output exactly once: \(exception.github)")
            expected = expected.replacingOccurrences(of: exception.github, with: exception.peep)
        }
        let actual = CorpusNormalizer.peep(HTMLRenderer().render(markdown).html)
        #expect(actual == expected, "\(name): \(CorpusNormalizer.firstDifference(actual, expected))")
        if let directory = ProcessInfo.processInfo.environment["PEEP_CORPUS_DIFF_DIR"], actual != expected {
            for (suffix, html) in [("peep", actual), ("github", expected)] {
                try html.write(toFile: "\(directory)/\(name).\(suffix).html", atomically: true, encoding: .utf8)
            }
        }
    }

    @Test("default output matches the recorded snapshot", arguments: names)
    func snapshot(_ name: String) throws {
        let html = HTMLRenderer().render(try Self.fixture(name, "md")).html
        if ProcessInfo.processInfo.environment["PEEP_RECORD_SNAPSHOTS"] != nil {
            let url = URL(filePath: #filePath).deletingLastPathComponent()
                .appending(components: "Fixtures", "corpus", "\(name).peep.html")
            try html.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let snapshot = try Self.fixture(name, "peep.html")
        #expect(html == snapshot, "\(name): \(CorpusNormalizer.firstDifference(html, snapshot))")
    }

    /// SPDX ids the corpus may use.
    static let permissiveLicenses: Set<String> = ["MIT", "Apache-2.0", "MIT OR Apache-2.0", "BSD-3-Clause", "CC0-1.0"]

    private static func fixtureURL(_ file: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: file, withExtension: nil, subdirectory: "Fixtures/corpus") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    private static func fixture(_ name: String, _ ext: String) throws -> String {
        try String(contentsOf: try fixtureURL("\(name).\(ext)"), encoding: .utf8)
    }
}

/// `Fixtures/corpus/corpus.json`.
struct CorpusManifest: Decodable {
    struct Document: Decodable {
        /// The file's URL on GitHub at `commit`.
        var source: String
        var commit: String
        /// SPDX license identifier of the source repository.
        var license: String
        var exceptions: [Exception]
    }

    /// A known difference: `github`, which must occur exactly once in GitHub's normalized
    /// output, is replaced with `peep` before comparing. Both are in normalized form.
    struct Exception: Decodable {
        var github: String
        var peep: String
        var reason: String
    }

    var documents: [String: Document]
}

/// Removes the differences between GitHub's and Peep's markup that are deliberate and apply to
/// every document (see the corpus README), then normalizes with `HTMLNormalizer`.
enum CorpusNormalizer {
    /// `html` is github.com's file view of a document; `hasFrontmatter` says whether the
    /// document starts with a YAML block, which GitHub shows as a leading table.
    static func github(_ html: String, hasFrontmatter: Bool = false) -> String {
        var html = replace(##" dir="auto""##, with: "", in: html)
        // The file view's wrapper.
        html = replace(
            ##"^<div id="file" class="md" data-path="[^"]*"><article [^>]*>([\s\S]*)</article></div>\s*$"##, with: "$1",
            in: html)
        if hasFrontmatter {
            html = replace(
                ##"^<markdown-accessiblity-table><table>[\s\S]*?</table></markdown-accessiblity-table>"##, with: "",
                in: html)
        }
        // Headings: GitHub wraps them and puts the id on a trailing anchor link.
        html = replace(
            ##"<div class="markdown-heading"><h([1-6])([^>]*?) class="heading-element"([^>]*)>([\s\S]*?)</h\1>"##
                + ##"<a id="user-content-([^"]*)" class="anchor" aria-label="[^"]*" href="#[^"]*">"##
                + ##"<svg [^>]*><path [^>]*></path></svg></a></div>"##,
            with: ##"<h$1$2$3 id="$5">$4</h$1>"##, in: html)
        // Code blocks: wrapped for the copy button; highlighted ones have no `<code>`.
        html = replace(
            ##"<div class="highlight[^"]*" data-snippet-clipboard-copy-content="[^"]*">"##
                + ##"<pre[^>]*>([\s\S]*?)</pre></div>"##,
            with: "<pre><code>$1</code></pre>", in: html)
        html = replace(
            ##"<div class="snippet-clipboard-content[^"]*" data-snippet-clipboard-copy-content="[^"]*">"##
                + ##"(<pre[^>]*>[\s\S]*?</pre>)</div>"##,
            with: "$1", in: html)
        html = siteMarkupRemoved(html)
        return normalized(html)
    }

    /// github.com's handling of images, emoji, links, and ids.
    private static func siteMarkupRemoved(_ html: String) -> String {
        var html = html
        // Images: unwrap the link GitHub adds around each image, and undo the camo proxy.
        html = replace(
            ##"<a target="_blank" rel="noopener noreferrer(?: nofollow)?" href="[^"]*">(<img [^>]*>)</a>"##, with: "$1",
            in: html)
        html = replace(
            ##"(src|srcset)="[^"]*"((?: [a-z-]+="[^"]*")*) data-canonical-src="([^"]*)""##, with: ##"$1="$3"$2"##,
            in: html)
        html = replace(##"(<img [^>]*?) style="[^"]*""##, with: "$1", in: html)
        // GitHub's custom (non-Unicode) emoji are remote images; Peep leaves the shortcode.
        html = replace(
            ##"<img class="emoji" title="(:[^"]*:)" alt="[^"]*" src="[^"]*""##
                + ##" height="20" width="20" align="absmiddle">"##,
            with: "$1", in: html)
        html = replace(##"<g-emoji class="g-emoji" alias="[^"]*">"##, with: "", in: html)
        // github.com shortens a bare link to an issue into `#123` (Peep keeps the URL), adds
        // hovercards to links, and serves user-attachment images from expiring signed URLs.
        html = replace(
            ##"<a class="issue-link js-issue-link"[^>]* href="([^"]*)">#\d+</a>"##, with: ##"<a href="$1">$1</a>"##,
            in: html)
        html = replace(##" data-hovercard-(?:type|url)="[^"]*""##, with: "", in: html)
        html = replace(
            ##"https://private-user-images\.githubusercontent\.com/\d+/\d+-([0-9a-f-]{36})\.[a-z]+\?jwt=[^"]*"##,
            with: "https://github.com/user-attachments/assets/$1", in: html)
        html = replace(##" data-animated-image="""##, with: "", in: html)
        // Footnote ids end in a per-render nonce.
        html = replace(##"-[0-9a-f]{32}(?=")"##, with: "", in: html)
        for literal in [
            "<markdown-accessiblity-table>", "</markdown-accessiblity-table>", " role=\"table\"", " rel=\"nofollow\"",
            " class=\"notranslate\"", " id=\"\"", "user-content-", "</g-emoji>",
            "<themed-picture data-catalyst-inline=\"true\">", "</themed-picture>",
        ] {
            html = html.replacingOccurrences(of: literal, with: "")
        }
        return html
    }

    static func peep(_ html: String) -> String {
        var html = replace(##" data-source-line="\d+""##, with: "", in: html)
        html = replace(##"<a class="anchor" aria-hidden="true" href="#[^"]*"></a>"##, with: "", in: html)
        html = replace(##"<code class="language-[^"]*">"##, with: "<code>", in: html)
        return normalized(html)
    }

    /// Applies the differences both sides share, then `HTMLNormalizer`:
    ///
    /// - Syntax-highlighting spans inside `<pre>` (GitHub's `pl-`, Peep's `hljs-`) are dropped,
    ///   and so is the newline ending a code block, which GitHub trims from highlighted code.
    /// - `"` in text is written literally (GitHub) or as `&quot;` (cmark); `&nbsp;` is decoded.
    private static func normalized(_ html: String) -> String {
        var output = ""
        var rest = html[...]
        while let open = rest.range(of: "<pre>"), let close = rest[open.upperBound...].range(of: "</pre>") {
            output += rest[..<open.upperBound]
            output += replace("</?span[^>]*>", with: "", in: String(rest[open.upperBound..<close.lowerBound]))
            output += "</pre>"
            rest = rest[close.upperBound...]
        }
        output += rest
        output = output.replacingOccurrences(of: "\n</code></pre>", with: "</code></pre>")
        // HTML parsers drop a newline right after `<pre>` (GitHub's output is re-serialized).
        output = output.replacingOccurrences(of: "<pre>\n", with: "<pre>")
        output = output.replacingOccurrences(of: "&nbsp;", with: "\u{A0}")
        return HTMLNormalizer.normalize(literalQuotesInText(output))
    }

    /// Replaces `&quot;` with `"` outside tags.
    private static func literalQuotesInText(_ html: String) -> String {
        var output = ""
        var rest = html[...]
        while let open = rest.firstIndex(of: "<") {
            output += rest[..<open].replacingOccurrences(of: "&quot;", with: "\"")
            let close = rest[open...].firstIndex(of: ">").map { rest.index(after: $0) } ?? rest.endIndex
            output += rest[open..<close]
            rest = rest[close...]
        }
        return output + rest.replacingOccurrences(of: "&quot;", with: "\"")
    }

    /// `NSRegularExpression` (ICU) rather than Swift `Regex`, which is far slower on these
    /// documents (some are over 250 KB).
    private static func replace(_ pattern: String, with template: String, in text: String) -> String {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            return regex.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
        } catch {
            preconditionFailure("bad pattern \(pattern): \(error)")
        }
    }

    /// Where two normalized outputs first differ, with some context, for failure messages.
    static func firstDifference(_ actual: String, _ expected: String) -> String {
        let actualScalars = Array(actual.unicodeScalars)
        let expectedScalars = Array(expected.unicodeScalars)
        var index = 0
        while index < min(actualScalars.count, expectedScalars.count), actualScalars[index] == expectedScalars[index] {
            index += 1
        }
        func excerpt(_ scalars: [Unicode.Scalar]) -> String {
            let start = max(0, index - 80)
            let end = min(scalars.count, index + 160)
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[start..<end])
            return String(view)
        }
        return
            "first difference at \(index)\n--- Peep\n\(excerpt(actualScalars))\n--- GitHub\n\(excerpt(expectedScalars))"
    }
}
