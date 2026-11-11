import ArgumentParser
import Foundation
import MdvCore

/// The `mdv` command. Each concern is an option group in its own file; this type only parses,
/// checks rules that span groups, and picks a mode. `run()` is the process entry;
/// `execute(in:)` is the same run against an injected `CLIEnvironment`, which the tests call.
///
/// Adding a flag: declare it in its concern's group (e.g. `RenderFlagOptions`), check it in that
/// group's `validate()`, and read it where the group is used (`apply(to:)`, `theme(for:)`,
/// `preprocess(_:)`, `AppOpening`). Only a rule spanning groups belongs in `validate()` here.
public struct MdvCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "mdv",
        abstract: "View Markdown files.",
        // The overview, examples, and exit statuses live in `HelpText` and `ExitStatus`, which
        // the man page's hand-written sections are built from too (#71).
        discussion: HelpText.discussion,
        version: MdvInfo.version
    )

    /// Placeholder until the final name is chosen; must match `PRODUCT_BUNDLE_IDENTIFIER_BASE`.
    public static let appBundleIdentifier = "com.itspriddle.mdv"

    @OptionGroup public var input: InputOptions
    @OptionGroup(title: "Output") public var output: OutputOptions
    @OptionGroup public var themeFlavor: ThemeFlavorOptions
    @OptionGroup(title: "Rendering") public var renderFlags: RenderFlagOptions
    @OptionGroup(title: "Preprocessor") public var preprocessor: PreprocessorOptions
    @OptionGroup public var app: AppOpenOptions

    public init() {}

    /// Rules that span groups (each group checks its own in its `validate()`).
    public func validate() throws {
        if themeFlavor.lists, !input.files.isEmpty {
            throw ValidationError("--list-themes and --list-flavors take no FILE.")
        }
        if renderFlags.isSet, !output.rendersHTML, !themeFlavor.lists {
            throw ValidationError("The Rendering flags change HTML output; add --html, --fragment, or --output.")
        }
        if preprocessor.isSet, !output.rendersHTML, !themeFlavor.lists {
            throw ValidationError(
                "--preprocessor changes HTML output only; add --html, --fragment, or --output.")
        }
        let inputCount = input.sources.count
        if output.output != nil, inputCount > 1 {
            throw ValidationError("--output takes one input; run mdv once per file.")
        }
        if output.rendersHTML, !output.fragment, inputCount > 1 {
            throw ValidationError(
                "Several inputs make one page each, which can't share an output; "
                    + "pass --fragment, or run mdv once per file.")
        }
    }

    public func run() async throws {
        let status = await execute(in: .live)
        if status != ExitStatus.success {
            throw ExitCode(status)
        }
    }

    /// Runs the parsed command and returns its exit status. Failures are reported on
    /// `environment.standardError` as one `mdv: …` line.
    public func execute(in environment: CLIEnvironment) async -> Int32 {
        if themeFlavor.lists {
            do {
                try themeFlavor.list(in: environment)
                return ExitStatus.success
            } catch {
                environment.reportError(error.message)
                return error.status
            }
        }
        if input.readsStandardInputImplicitly, environment.standardInputIsTerminal {
            environment.reportError("no FILE given and standard input is a terminal")
            let hint = "Usage: \(Self.usageString())\n  See 'mdv --help'.\n"
            try? environment.standardError.write(Data(hint.utf8))
            return ExitStatus.usage
        }
        do {
            if output.rendersHTML {
                try await writeHTML(in: environment)
            } else {
                try await openInApp(in: environment)
            }
            return ExitStatus.success
        } catch {
            environment.reportError(error.message)
            return error.status
        }
    }
}
