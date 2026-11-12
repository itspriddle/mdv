import Foundation
import Testing

/// One example from a cmark-style spec file (`spec.txt`, `extensions.txt`, `regression.txt`).
struct SpecExample: Sendable, CustomTestStringConvertible {
    /// The spec file's name, e.g. `spec.txt`.
    var file: String
    /// 1-based example number within `file`, counted the way cmark's `spec_tests.py` counts them
    /// (disabled examples still take a number).
    var number: Int
    /// The nearest preceding Markdown heading.
    var section: String
    /// Line of the opening fence in `file`.
    var line: Int
    /// Words after `example` on the opening fence, e.g. `["table", "footnotes"]`.
    var tags: [String]
    var markdown: String
    var html: String

    var isDisabled: Bool { tags.contains("disabled") }

    var testDescription: String { "\(file) #\(number) (\(section))" }
}

enum SpecFileError: Error, CustomStringConvertible {
    case missing(String)
    case notUTF8(String)
    case unterminatedExample(file: String, line: Int)

    var description: String {
        switch self {
        case .missing(let file): "spec fixture \(file) not found in the test bundle"
        case .notUTF8(let file): "spec fixture \(file) is not valid UTF-8"
        case .unterminatedExample(let file, let line): "\(file):\(line): example is not closed"
        }
    }
}

/// Parses the spec example format, mirroring `get_tests` in cmark's `test/spec_tests.py`:
///
///     ```````````````````````````````` example [tags...]
///     markdown
///     .
///     expected html
///     ````````````````````````````````
///
/// `→` stands for a tab in both halves. Lines are split on LF only, so the CRs some regression
/// examples depend on survive.
enum SpecParser {
    private static let fence = String(repeating: "`", count: 32)
    private static let exampleFence = fence + " example"

    static func parse(_ text: String, file: String) throws -> [SpecExample] {
        enum State {
            case prose
            case markdown
            case html
        }

        var examples: [SpecExample] = []
        var state = State.prose
        var section = ""
        var tags: [String] = []
        var startLine = 0
        var markdown = ""
        var html = ""

        // Split on LF bytes: `String.split` would treat CR LF as one character.
        let lines = text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        for (index, bytes) in lines.enumerated() {
            let lineNumber = index + 1
            let line = String(Substring(bytes))
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix(exampleFence) {
                state = .markdown
                startLine = lineNumber
                tags = trimmed.dropFirst(exampleFence.count).split(separator: " ").map(String.init)
            } else if trimmed == fence, state != .prose {
                examples.append(
                    SpecExample(
                        file: file,
                        number: examples.count + 1,
                        section: section,
                        line: startLine,
                        tags: tags,
                        markdown: markdown.replacingOccurrences(of: "→", with: "\t"),
                        html: html.replacingOccurrences(of: "→", with: "\t")))
                state = .prose
                markdown = ""
                html = ""
            } else if trimmed == ".", state == .markdown {
                state = .html
            } else {
                switch state {
                case .markdown: markdown += line + "\n"
                case .html: html += line + "\n"
                case .prose: section = heading(in: line) ?? section
                }
            }
        }
        if state != .prose {
            throw SpecFileError.unterminatedExample(file: file, line: startLine)
        }
        return examples
    }

    /// The text of an ATX heading line (`#+ ` prefix), or `nil`.
    private static func heading(in line: String) -> String? {
        let hashes = line.prefix { $0 == "#" }
        guard !hashes.isEmpty, line.dropFirst(hashes.count).first == " " else {
            return nil
        }
        return line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
    }
}
