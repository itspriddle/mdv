import Foundation
import PeepCore

/// The `peep(1)` man page (#71). ArgumentParser's `generate-manual` plugin writes NAME, SYNOPSIS,
/// and the option list from the command itself (`make man` runs it), so a new flag appears
/// without touching this file. `finish(_:)` replaces what the generator can't do well and adds
/// the hand-written sections, each built from the code it documents:
///
/// - DESCRIPTION: `HelpText.overview` in place of the help's discussion (whose examples and exit
///   statuses get sections of their own), then the generated option list.
/// - ENVIRONMENT and FILES: the Themes folder (`ThemeResolver`).
/// - EXIT STATUS: `ExitStatus.entries` in place of the generator's generic sentence.
/// - EXAMPLES: `HelpText.examples`.
/// - SECURITY CONSIDERATIONS: what the CLI does and doesn't do with an untrusted document, and
///   what `--preprocessor` runs (`PreprocessorLimits.standard`).
///
/// ArgumentParser lists its implicit `help` subcommand; Peep has no subcommands, so the SYNOPSIS
/// placeholder and the list entry are removed.
public enum ManualPage {
    /// Why `finish(_:)` couldn't use the generator's output (its format changed).
    public struct FormatError: Error, CustomStringConvertible, Equatable {
        public let description: String
    }

    /// `~/Library/Application Support/Peep/Themes`, as a reader would type it
    /// (`ThemeResolver.themesFolder(environment:)` without `PEEP_THEMES_FOLDER`).
    static let themesFolderDisplayPath = "~/Library/Application Support/Peep/Themes"

    /// The preprocessor's document path variable (PeepCore's `PreprocessorEnvironment`).
    static let documentPathVariable = "PEEP_DOCUMENT_PATH"

    /// `generated` (a `peep.1` from `generate-manual`) with Peep's sections.
    public static func finish(_ generated: String) throws(FormatError) -> String {
        var page = try Page(parsing: generated)
        try page.edit("SYNOPSIS") { $0.removeAll { $0 == ".Ar subcommand" } }
        try page.edit("DESCRIPTION") { body throws(FormatError) in
            body = try description(fromGenerated: body)
        }
        page.remove("EXIT STATUS")
        page.insert(
            after: "DESCRIPTION",
            [
                Section(title: "ENVIRONMENT", body: environment),
                Section(title: "FILES", body: files),
                Section(title: "EXIT STATUS", body: exitStatus),
                Section(title: "EXAMPLES", body: examples),
            ])
        page.sections.append(Section(title: "SECURITY CONSIDERATIONS", body: security))
        return page.serialized
    }

    // MARK: - Sections

    /// The overview, then the generated option list without the `help` subcommand's entry.
    private static func description(fromGenerated body: [String]) throws(FormatError) -> [String] {
        guard let listStart = body.firstIndex(where: { $0.hasPrefix(".Bl ") }) else {
            throw FormatError(description: "DESCRIPTION has no option list (.Bl)")
        }
        var options = Array(body[listStart...])
        if let help = options.firstIndex(of: ".It Em help") {
            options.removeSubrange(help..<endOfItem(startingAt: help, in: options))
        }
        let overview = HelpText.overview.map(text).joined(separator: "\n.Pp\n")
        return overview.components(separatedBy: "\n") + options
    }

    /// The index just past the list item at `start`: the next item or the end of its list, at
    /// the same nesting level.
    private static func endOfItem(startingAt start: Int, in lines: [String]) -> Int {
        var depth = 0
        var index = start + 1
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix(".Bl") {
                depth += 1
            } else if line == ".El" {
                if depth == 0 {
                    return index
                }
                depth -= 1
            } else if depth == 0, line.hasPrefix(".It") {
                return index
            }
            index += 1
        }
        return index
    }

    private static var environment: [String] {
        [
            ".Bl -tag -width Ds",
            ".It Ev \(ThemeResolver.themesFolderVariable)",
            text(
                "The Themes folder that custom: themes are read from (--theme, --list-themes, shell "
                    + "completion of --theme, and a document's peep.theme), instead of \(themesFolderDisplayPath)."),
            ".El",
        ]
    }

    private static var files: [String] {
        [
            ".Bl -tag -width Ds",
            ".It Pa \(quoted(themesFolderDisplayPath))",
            text(
                "The Themes folder the app uses too (View > Theme > Open Themes Folder): one CSS file "
                    + "per custom theme, used as custom:<file name>. --list-themes lists the themes that load "
                    + "and reports the files that don't."),
            ".El",
        ]
    }

    private static var exitStatus: [String] {
        var lines = [".Bl -tag -width Ds"]
        for entry in ExitStatus.entries {
            lines += [
                ".It \(entry.status)", text(entry.meaning.prefix(1).uppercased() + entry.meaning.dropFirst() + "."),
            ]
        }
        lines += [".El", ".Pp", text(ExitStatus.interruptNote)]
        return lines
    }

    private static var examples: [String] {
        var lines: [String] = []
        for (index, example) in HelpText.examples.enumerated() {
            if index > 0 {
                lines.append(".Pp")
            }
            lines += [text(example.explanation), ".Bd -literal -offset indent", text(example.command), ".Ed"]
        }
        return lines
    }

    private static var security: [String] {
        let limits = PreprocessorLimits.standard
        let seconds = limits.timeout.components.seconds
        let megabytes = limits.maximumInputBytes / (1024 * 1024)
        let paragraphs = [
            "Treat a Markdown file like any other document from its source. In the app, page "
                + "JavaScript is off, and remote images load only when you ask in that window.",
            "HTML output (--html, --fragment, --output) is meant for a browser, where JavaScript "
                + "runs, so raw HTML in the document is always sanitized; there is no flag to turn that "
                + "off. Pages carry a strict Content-Security-Policy that allows no scripts and no remote "
                + "loads, and remote images become placeholders with --block-remote-images.",
            "Peep never runs a program unless --preprocessor names one. The CLI doesn't use the "
                + "preprocessor configured in the app, and a document's frontmatter can't turn one on. "
                + "The program runs as you, with your file access, so name only programs you trust. "
                + "It gets the document on standard input and no arguments but --preprocessor-arg's, "
                + "a minimal environment with the document's path in \(documentPathVariable), and the "
                + "document's folder as its working directory (/ for standard input). It is stopped "
                + "after \(seconds) seconds, and an input or output over \(megabytes) MB fails the run.",
        ]
        return paragraphs.map(text).joined(separator: "\n.Pp\n").components(separatedBy: "\n")
    }

    // MARK: - mdoc

    /// `string` as mdoc text lines: one sentence per line (as mdoc expects, so it can space
    /// sentences), backslashes escaped, and a line that would start with a control character
    /// (`.` or `'`) protected with `\&`.
    static func text(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\e")
            .replacingOccurrences(of: ". ", with: ".\n")
            .replacingOccurrences(of: "; ", with: ";\n")
            .components(separatedBy: "\n")
            .map { $0.hasPrefix(".") || $0.hasPrefix("'") ? "\\&" + $0 : $0 }
            .joined(separator: "\n")
    }

    /// `string` as one macro argument (in double quotes, which mdoc writes as `\(dq`).
    private static func quoted(_ string: String) -> String {
        "\"" + text(string).replacingOccurrences(of: "\"", with: "\\(dq") + "\""
    }
}

// MARK: - Page structure

extension ManualPage {
    /// A man page as its lines before the first `.Sh` and its sections.
    fileprivate struct Page {
        var preamble: [String]
        var sections: [Section]

        init(parsing source: String) throws(FormatError) {
            var lines = source.components(separatedBy: "\n")
            while lines.last?.isEmpty == true {
                lines.removeLast()
            }
            guard let first = lines.firstIndex(where: { $0.hasPrefix(".Sh ") }) else {
                throw FormatError(description: "no sections (.Sh)")
            }
            preamble = Array(lines[..<first])
            sections = []
            for line in lines[first...] {
                if line.hasPrefix(".Sh ") {
                    sections.append(Section(title: Section.title(ofHeader: line), body: []))
                } else {
                    sections[sections.count - 1].body.append(line)
                }
            }
            for required in ["NAME", "SYNOPSIS", "DESCRIPTION"]
            where !sections.contains(where: { $0.title == required }) {
                throw FormatError(description: "no \(required) section")
            }
        }

        mutating func edit(_ title: String, _ change: (inout [String]) throws(FormatError) -> Void) throws(FormatError)
        {
            guard let index = sections.firstIndex(where: { $0.title == title }) else {
                throw FormatError(description: "no \(title) section")
            }
            try change(&sections[index].body)
        }

        mutating func remove(_ title: String) {
            sections.removeAll { $0.title == title }
        }

        mutating func insert(after title: String, _ new: [Section]) {
            let index = sections.firstIndex { $0.title == title }.map { $0 + 1 } ?? sections.endIndex
            sections.insert(contentsOf: new, at: index)
        }

        var serialized: String {
            let header = [
                #".\" Generated by `make man` (ArgumentParser's generate-manual, then ManualPage); don't edit."#
            ]
            let lines = preamble + header + sections.flatMap { [$0.header] + $0.body }
            return lines.joined(separator: "\n") + "\n"
        }
    }

    fileprivate struct Section {
        var title: String
        var body: [String]

        var header: String {
            title.contains(" ") ? ".Sh \"\(title)\"" : ".Sh \(title)"
        }

        /// `NAME` from `.Sh NAME`, `EXIT STATUS` from `.Sh "EXIT STATUS"`.
        static func title(ofHeader line: String) -> String {
            String(line.dropFirst(".Sh ".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                .uppercased()
        }
    }
}
