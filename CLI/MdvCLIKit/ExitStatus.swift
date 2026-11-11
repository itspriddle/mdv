import ArgumentParser

/// mdv's exit statuses, from `sysexits(3)`. `MdvCommand`'s help (`ExitStatus.help`), the README,
/// and VISION list them; keep all four in sync.
public enum ExitStatus {
    public static let success: Int32 = 0
    /// Bad flags or arguments (ArgumentParser's `ValidationError` exits with this too).
    public static let usage: Int32 = ExitCode.validationFailure.rawValue
    /// An input isn't valid UTF-8, or the `--theme` file isn't a valid theme.
    public static let dataError: Int32 = 65
    /// An input file is missing or unreadable, or the `--theme` file is missing.
    public static let noInput: Int32 = 66
    /// The app couldn't be opened.
    public static let unavailable: Int32 = 69
    /// The `--output` file couldn't be written.
    public static let cannotCreate: Int32 = 73
    /// Writing to standard output failed.
    public static let ioError: Int32 = 74

    /// The exit status section of `mdv --help`.
    static let help = """
        EXIT STATUS:
          0   success
          64  usage error: bad flags, several pages to one output, --output
              naming an input, or no FILE while standard input is a terminal
          65  an input isn't valid UTF-8, or the --theme file isn't a valid theme
          66  an input file is missing or unreadable, or the --theme file is
              missing
          69  the app couldn't be opened
          73  the --output file couldn't be written
          74  writing to standard output failed
        """
}
