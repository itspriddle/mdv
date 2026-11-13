import ArgumentParser

/// `peep`'s shell completion scripts: ArgumentParser's, without the `help` subcommand it adds.
///
/// swift-argument-parser (1.8.2, and its main branch as of November 2026) builds every script
/// from a `ToolInfoV0` that always appends a `help` subcommand to the root command ("FIXME: This
/// is a hack" in `DumpHelpGenerator.swift`), even one with no subcommands. `peep` takes a variadic
/// `FILE...`, so the zsh script had two rest-argument specs, `'*:FILE:_files'` and the subcommand
/// dispatch's `'(-)*:: :->arg'`, and `_arguments` refused it on every Tab ("doubled rest argument
/// definition"). The fish script offered `help` as a second FILE. bash's script is used as is:
/// its positional case returns before the subcommand branch, so `help` is never offered.
///
/// ArgumentParser has no option to leave the subcommand out, so `script(for:)` removes the lines
/// that add it. Each removal must match exactly once; if a newer ArgumentParser writes something
/// else, it throws, which fails `make cli-docs`, the app's build phase that bundles the scripts,
/// and `CompletionTests`, rather than shipping a different broken script. `PeepCommand.main()`
/// prints these for `--generate-completion-script`, so every copy is the same script.
public enum CompletionScript {
    /// ArgumentParser's script didn't contain a line `script(for:)` removes, exactly once.
    public struct MismatchError: Error, CustomStringConvertible {
        public let shell: CompletionShell
        public let expected: String

        public var description: String {
            "ArgumentParser's \(shell.rawValue) completion script changed; CompletionScript expected once:\n\(expected)"
        }
    }

    /// The script for `shell`.
    public static func script(for shell: CompletionShell) throws -> String {
        // Whole lines: matched with the newlines around them (the one added here lets the last
        // line go too, and comes off at the end).
        var script = PeepCommand.completionScript(for: shell) + "\n"
        for lines in removals(for: shell) {
            let ranges = script.ranges(of: "\n" + lines + "\n")
            guard ranges.count == 1, let range = ranges.first else {
                throw MismatchError(shell: shell, expected: lines)
            }
            script.replaceSubrange(range, with: "\n")
        }
        return String(script.dropLast())
    }

    /// The lines each shell's script loses (whole lines, without the final newline).
    static func removals(for shell: CompletionShell) -> [String] {
        switch shell {
        case .zsh:
            // The subcommand dispatch's two specs. Without them `state` is never set, so the
            // `case "${state}"` block and `_peep_help` that follow are never reached.
            [
                "        '(-): :->command'",
                "        '(-)*:: :->arg'",
            ]
        case .fish:
            [
                """
                        switch $unparsed_tokens[1]
                        case 'help'
                            __peep_parse_subcommand -r 1 'version'
                        end
                """,
                "complete -c 'peep' -n '__peep_should_offer_completions_for_positional \"peep\" -eq 2' "
                    + "-fa 'help' -d 'Show subcommand help information.'",
                "complete -c 'peep' -n '__peep_should_offer_completions_for_flags_or_options \"peep help\" version' "
                    + "-l 'version' -d 'Show the version.'",
            ]
        default:
            []
        }
    }

    /// The shell whose script ArgumentParser would print for a parse error, or nil when it isn't
    /// a `--generate-completion-script` request. ArgumentParser's request error is internal, so
    /// this compares the message it would print with each shell's script.
    static func requestedShell(by error: any Error) -> CompletionShell? {
        guard PeepCommand.exitCode(for: error) == .success else {
            return nil
        }
        let message = PeepCommand.fullMessage(for: error)
        return CompletionShell.allCases.first { PeepCommand.completionScript(for: $0) == message }
    }
}

extension PeepCommand {
    /// The process entry (`CLI/Main`): `AsyncParsableCommand.main()`, except that
    /// `--generate-completion-script` prints `CompletionScript.script(for:)`.
    public static func main() async {
        do {
            var command = try await asyncParseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            guard let shell = CompletionScript.requestedShell(by: error) else {
                exit(withError: error)
            }
            do {
                print(try CompletionScript.script(for: shell))
                exit()
            } catch {
                CLIEnvironment.live.reportError("\(error)")
                exit(withError: ExitCode.failure)
            }
        }
    }
}
