import Foundation

/// The `mdv` commands in the README's `sh` blocks (#72), so every example there is run or parsed
/// by `ReadmeExampleTests`. Reads just enough shell for the README: words, single and double
/// quotes, `#` comments, `|`, `>`, `&&`, and `;`. Anything fancier in an `mdv` example is
/// reported as unsupported, so the test fails instead of skipping it.
struct ReadmeExample: CustomStringConvertible {
    /// The README line it came from (1-based) and its text.
    let line: Int
    let text: String
    /// The words after `mdv`, up to the first redirection.
    let arguments: [String]
    /// What a pipeline feeds `mdv`: `echo`'s words (plus a newline), or `nil` for no pipe. A pipe
    /// from another command (`git show …`) gets `placeholderInput`.
    let standardInput: String?
    /// `> FILE` after `mdv`, if any.
    let redirectedOutput: String?

    static let placeholderInput = "# Piped example\n"

    var description: String { "README.md:\(line): \(text)" }

    /// Flags that make `mdv` print or write instead of opening the app.
    private static let headlessFlags: Set = [
        "--html", "--fragment", "-o", "--output", "--list-themes", "--list-flavors",
        "--generate-completion-script", "--help", "-h", "--version",
    ]

    /// Runs without the app: renders HTML or prints a list.
    var isHeadless: Bool { arguments.contains { Self.headlessFlags.contains($0) } }

    /// The Markdown inputs it names (`*.md`), which a test creates before running it.
    var inputFiles: [String] { arguments.filter { $0.hasSuffix(".md") } }
}

enum ReadmeExamples {
    /// The repository's README.md (this file is at Tests/MdvCLITests/Support/).
    static var readmeURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "README.md")
    }

    /// The lines of every ```` ```sh ```` block, with their 1-based line numbers.
    static func shellLines(in markdown: String) -> [(line: Int, text: String)] {
        var lines: [(Int, String)] = []
        var inShell = false
        for (index, line) in markdown.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inShell = !inShell && trimmed == "```sh"
            } else if inShell {
                lines.append((index + 1, String(line)))
            }
        }
        return lines
    }

    /// The `mdv` commands in `markdown`'s `sh` blocks, and the lines with an `mdv` command this
    /// reader doesn't understand.
    static func examples(in markdown: String) -> (examples: [ReadmeExample], unsupported: [String]) {
        var examples: [ReadmeExample] = []
        var unsupported: [String] = []
        for (line, text) in shellLines(in: markdown) {
            guard let segments = ShellWords.segments(text) else {
                if text.contains("mdv ") { unsupported.append("README.md:\(line): \(text)") }
                continue
            }
            for (index, segment) in segments.enumerated() where segment.words.first == "mdv" {
                guard let example = example(segments, at: index, line: line, text: text) else {
                    unsupported.append("README.md:\(line): \(text)")
                    continue
                }
                examples.append(example)
            }
        }
        return (examples, unsupported)
    }

    /// Words like `"$completions/_mdv"`: the completion scripts a block links to.
    static func completionScriptNames(in markdown: String) -> [String] {
        shellLines(in: markdown).flatMap { _, text in
            (ShellWords.segments(text) ?? []).flatMap(\.words).compactMap { word in
                word.hasPrefix("$completions/") ? String(word.dropFirst("$completions/".count)) : nil
            }
        }
    }

    private static func example(_ segments: [ShellWords.Segment], at index: Int, line: Int, text: String)
        -> ReadmeExample?
    {
        let segment = segments[index]
        var standardInput: String?
        if index > 0 {
            let producer = segments[index - 1]
            guard producer.separator == "|" else { return nil }
            standardInput =
                producer.words.first == "echo"
                ? producer.words.dropFirst().joined(separator: " ") + "\n" : ReadmeExample.placeholderInput
        }
        var arguments = Array(segment.words.dropFirst())
        var redirectedOutput: String?
        if let redirect = arguments.firstIndex(of: ">") {
            guard redirect + 2 == arguments.count else { return nil }
            redirectedOutput = arguments[redirect + 1]
            arguments.removeSubrange(redirect...)
        }
        if arguments.contains(where: { $0.contains("$") || $0.contains("*") || $0 == "<" }) { return nil }
        return ReadmeExample(
            line: line, text: text.trimmingCharacters(in: .whitespaces), arguments: arguments,
            standardInput: standardInput, redirectedOutput: redirectedOutput)
    }
}

/// Splits one line of shell into commands (`|`, `&&`, `;`) of words. `>` is kept as a word.
/// Returns `nil` for what it doesn't read (unterminated quotes, backslashes, `$(`, backticks).
enum ShellWords {
    struct Segment {
        var words: [String] = []
        /// What followed this command: `|`, `&&`, `;`, or `nil` at the end of the line.
        var separator: String?
    }

    static func segments(_ line: String) -> [Segment]? {
        var segments: [Segment] = []
        var current = Segment()
        var word: String?
        var quote: Character?
        var characters = Array(line)[...]
        func endWord() {
            if let finished = word { current.words.append(finished) }
            word = nil
        }
        while let character = characters.popFirst() {
            if let open = quote {
                if character == open { quote = nil } else { word = (word ?? "") + String(character) }
                continue
            }
            switch character {
            case "'", "\"":
                quote = character
                word = word ?? ""
            case "\\", "`":
                return nil
            case "#" where word == nil:
                characters = []
            case " ", "\t":
                endWord()
            case "|", ";", "&":
                endWord()
                var separator = String(character)
                if character == "&" {
                    guard characters.popFirst() == "&" else { return nil }
                    separator = "&&"
                }
                current.separator = separator
                segments.append(current)
                current = Segment()
            case ">":
                endWord()
                current.words.append(">")
            default:
                if character == "(", word?.hasSuffix("$") == true { return nil }
                word = (word ?? "") + String(character)
            }
        }
        guard quote == nil else { return nil }
        endWord()
        if !current.words.isEmpty { segments.append(current) }
        return segments
    }
}
