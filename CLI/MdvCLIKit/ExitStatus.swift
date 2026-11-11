import ArgumentParser

/// mdv's exit statuses, from `sysexits(3)`. `MdvCommand`'s help (`ExitStatus.help`), the README,
/// and VISION list them; keep all four in sync.
public enum ExitStatus {
    public static let success: Int32 = 0
    /// Bad flags or arguments (ArgumentParser's `ValidationError` exits with this too).
    public static let usage: Int32 = ExitCode.validationFailure.rawValue
    /// An input isn't valid UTF-8, standard input is too large for a window (#68), or the
    /// `--theme` file isn't a valid theme.
    public static let dataError: Int32 = 65
    /// An input file is missing or unreadable, standard input for a window is empty (#68), or
    /// the `--theme` file is missing.
    public static let noInput: Int32 = 66
    /// The app couldn't be opened.
    public static let unavailable: Int32 = 69
    /// The `--preprocessor` program couldn't run or failed (#66).
    public static let software: Int32 = 70
    /// The `--output` file couldn't be written.
    public static let cannotCreate: Int32 = 73
    /// Writing to standard output failed.
    public static let ioError: Int32 = 74
    /// A `--preprocessor` run was cancelled by a signal that didn't then end the process
    /// (128 + `SIGINT`, as shells report it). Normally the signal itself ends mdv.
    public static let interrupted: Int32 = 130

    /// One documented exit status: the code and what it means.
    public struct Entry: Sendable, Equatable {
        public let status: Int32
        public let meaning: String
    }

    /// The statuses `mdv --help` and the man page list, in order (#71: the man page's EXIT
    /// STATUS section is built from this, so a status is documented here once).
    public static let entries: [Entry] = [
        Entry(status: success, meaning: "success"),
        Entry(
            status: usage,
            meaning: "usage error: bad flags, several pages to one output, --output naming an input, "
                + "or no FILE while standard input is a terminal"),
        Entry(
            status: dataError,
            meaning: "an input isn't valid UTF-8, standard input is over 10 MB for a window, "
                + "or the --theme file isn't a valid theme"),
        Entry(
            status: noInput,
            meaning: "an input file is missing or unreadable, standard input for a window is empty, "
                + "or the --theme file is missing"),
        Entry(status: unavailable, meaning: "the app couldn't be opened"),
        Entry(status: software, meaning: "the --preprocessor program couldn't run or failed"),
        Entry(status: cannotCreate, meaning: "the --output file couldn't be written"),
        Entry(status: ioError, meaning: "writing to standard output failed"),
    ]

    /// What happens on Ctrl-C (`interrupted`), after the list.
    public static let interruptNote = "Ctrl-C during a --preprocessor run stops the program, then mdv."

    /// The exit status section of `mdv --help`: `entries`, wrapped to 74 columns.
    static var help: String {
        var lines = ["EXIT STATUS:"]
        for entry in entries {
            let code = String(entry.status)
            let label = "  " + code + String(repeating: " ", count: max(1, 4 - code.count))
            lines += HelpText.wrap(entry.meaning, width: 74, firstPrefix: label, prefix: "      ")
        }
        lines += HelpText.wrap(interruptNote, width: 74, firstPrefix: "  ", prefix: "  ")
        return lines.joined(separator: "\n")
    }
}
