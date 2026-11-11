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
        discussion: """
            Opens FILE(s) in mdv. With no FILE, reads Markdown from standard input.
            --html, --fragment, or --output render HTML instead of opening the app.

              mdv README.md
              echo '# Markdown' | mdv
              mdv --html README.md > README.html
              mdv -o README.html README.md
              mdv --fragment intro.md usage.md > body.html
              mdv --html --theme serif --flavor commonmark notes.md

            Several FILEs print one after another only with --fragment; --output takes one.

            \(ExitStatus.help)
            """,
        version: MdvInfo.version
    )

    /// Placeholder until the final name is chosen; must match `PRODUCT_BUNDLE_IDENTIFIER_BASE`.
    public static let appBundleIdentifier = "com.itspriddle.mdv"

    @OptionGroup public var input: InputOptions
    @OptionGroup(title: "Output") public var output: OutputOptions
    @OptionGroup public var themeFlavor: ThemeFlavorOptions
    @OptionGroup public var renderFlags: RenderFlagOptions
    @OptionGroup public var preprocessor: PreprocessorOptions
    @OptionGroup public var app: AppOpenOptions

    public init() {}

    /// Rules that span groups (each group checks its own in its `validate()`).
    public func validate() throws {
        if themeFlavor.lists, !input.files.isEmpty {
            throw ValidationError("--list-themes and --list-flavors take no FILE.")
        }
        if themeFlavor.flavor != nil, !output.rendersHTML, !themeFlavor.lists {
            throw ValidationError(
                "--flavor is for --html, --fragment, and --output; windows use Settings > Markdown "
                    + "or the document's mdv.flavor.")
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
