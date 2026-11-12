/// Text that `peep --help` and the man page share (#71), so neither goes stale. The flags
/// themselves are documented once, in their option groups; ArgumentParser generates both the
/// help's option list and the man page's from them.
public enum HelpText {
    /// What Peep does, one paragraph each: the help's discussion and the man page's DESCRIPTION.
    public static let overview = [
        "Opens FILE(s) in Peep. With no FILE, reads Markdown from standard input. "
            + "--html, --fragment, or --output render HTML instead of opening the app.",
        "Several FILEs print one after another only with --fragment; --output takes one.",
        "Standard input opens in an untitled window (up to 10 MB, read to its end, no file left "
            + "behind); '-' adds it to FILEs.",
    ]

    /// One usage example: the command line and what it does.
    public struct Example: Sendable, Equatable {
        public let command: String
        public let explanation: String
    }

    /// The help's examples (commands only) and the man page's EXAMPLES section.
    public static let examples = [
        Example(command: "peep README.md", explanation: "Open README.md in Peep."),
        Example(
            command: "peep --wait notes.md",
            explanation: "Open notes.md and return once its window closes (or Peep quits)."),
        Example(
            command: "echo '# Markdown' | peep", explanation: "Open Markdown from standard input in a new window."),
        Example(
            command: "git show HEAD:README.md | peep --wait",
            explanation: "Open the committed README in a new window and return once it closes."),
        Example(
            command: "peep --html README.md > README.html",
            explanation: "Render a complete HTML page, CSS inline, to standard output."),
        Example(
            command: "peep -o README.html README.md",
            explanation: "Write the page to README.html, replacing it atomically."),
        Example(
            command: "peep --fragment intro.md usage.md > body.html",
            explanation: "Render the body HTML of two files, one after the other, for embedding in another page."),
        Example(
            command: "peep --html --theme serif --flavor commonmark notes.md",
            explanation:
                "Render with the Serif theme and plain CommonMark, whatever the document's frontmatter asks for."),
        Example(
            command: "peep --html --preprocessor ~/bin/expand --preprocessor-arg -v notes.md",
            explanation: "Run ~/bin/expand -v on the Markdown first and render what it prints."),
    ]

    /// `PeepCommand`'s help discussion: the overview, the example commands, and the exit statuses.
    static var discussion: String {
        let commands = examples.map { "  " + $0.command }.joined(separator: "\n")
        return """
            \(overview[0])

            \(commands)

            \(overview.dropFirst().joined(separator: "\n\n"))

            \(ExitStatus.help)
            """
    }

    /// `text` wrapped at spaces to lines of at most `width` columns (a longer word gets a line of
    /// its own): the first line starts with `firstPrefix`, the rest with `prefix`.
    static func wrap(_ text: String, width: Int, firstPrefix: String, prefix: String) -> [String] {
        var lines: [String] = []
        var line = firstPrefix
        var lineHasWord = false
        for word in text.split(separator: " ") {
            if lineHasWord, line.count + 1 + word.count > width {
                lines.append(line)
                line = prefix
                lineHasWord = false
            }
            line += (lineHasWord ? " " : "") + word
            lineHasWord = true
        }
        lines.append(line)
        return lines
    }
}
