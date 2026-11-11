/// Text that `mdv --help` and the man page share (#71), so neither goes stale. The flags
/// themselves are documented once, in their option groups; ArgumentParser generates both the
/// help's option list and the man page's from them.
public enum HelpText {
    /// What mdv does, one paragraph each: the help's discussion and the man page's DESCRIPTION.
    public static let overview = [
        "Opens FILE(s) in mdv. With no FILE, reads Markdown from standard input. "
            + "--html, --fragment, or --output render HTML instead of opening the app.",
        "Several FILEs print one after another only with --fragment; --output takes one.",
    ]

    /// One usage example: the command line and what it does.
    public struct Example: Sendable, Equatable {
        public let command: String
        public let explanation: String
    }

    /// The help's examples (commands only) and the man page's EXAMPLES section.
    public static let examples = [
        Example(command: "mdv README.md", explanation: "Open README.md in mdv."),
        Example(
            command: "mdv --wait notes.md",
            explanation: "Open notes.md and return once its window closes (or mdv quits)."),
        Example(
            command: "echo '# Markdown' | mdv", explanation: "Open Markdown from standard input in a new window."),
        Example(
            command: "mdv --html README.md > README.html",
            explanation: "Render a complete HTML page, CSS inline, to standard output."),
        Example(
            command: "mdv -o README.html README.md",
            explanation: "Write the page to README.html, replacing it atomically."),
        Example(
            command: "mdv --fragment intro.md usage.md > body.html",
            explanation: "Render the body HTML of two files, one after the other, for embedding in another page."),
        Example(
            command: "mdv --html --theme serif --flavor commonmark notes.md",
            explanation:
                "Render with the Serif theme and plain CommonMark, whatever the document's frontmatter asks for."),
        Example(
            command: "mdv --html --preprocessor ~/bin/expand --preprocessor-arg -v notes.md",
            explanation: "Run ~/bin/expand -v on the Markdown first and render what it prints."),
    ]

    /// `MdvCommand`'s help discussion: the overview, the example commands, and the exit statuses.
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
