import ArgumentParser
import Foundation
import Testing

@testable import PeepCLIKit

/// Shell completions (#71): ArgumentParser's scripts, plus `--theme`'s dynamic ids.
@Suite("Shell completions")
struct CompletionTests {
    private static let shells: [CompletionShell] = [.zsh, .bash, .fish]
    private static let theme = "/* peep-theme\n   name: Test Theme\n*/\nbody { color: #123456; }\n"

    @Test("each shell's script offers every option of PeepCommand", arguments: shells)
    func everyOption(shell: CompletionShell) throws {
        let script = try CompletionScript.script(for: shell)
        let options = try #require(try CommandOptions.load())
        for option in options.options {
            for spelling in option.spellings where spelling.hasPrefix("--") {
                // fish writes `-l 'output'`; zsh and bash write `--output`.
                let name = String(spelling.dropFirst(2))
                #expect(script.contains(shell == .fish ? "-l '\(name)'" : spelling), "\(spelling) missing for \(shell)")
            }
        }
    }

    @Test("FILE, --output, and --preprocessor complete file names", arguments: shells)
    func files(shell: CompletionShell) throws {
        let script = try CompletionScript.script(for: shell)
        let lines = script.components(separatedBy: "\n")
        switch shell {
        case .zsh:
            #expect(lines.contains { $0.contains("'*:FILE:_files'") })
            #expect(lines.contains { $0.contains("--output}'[") && $0.hasSuffix(":FILE:_files'") })
            #expect(lines.contains { $0.contains("'--preprocessor[") && $0.hasSuffix(":PATH:_files'") })
        case .bash:
            // The positional case, --output's, and --preprocessor's.
            #expect(lines.filter { $0.contains("__peep_add_completions -f") }.count == 3)
        default:
            #expect(lines.contains { $0.hasSuffix("-ge 1' -F") })
            #expect(lines.contains { $0.contains("-l 'output'") && $0.hasSuffix(" -rF") })
            #expect(lines.contains { $0.contains("-l 'preprocessor'") && $0.hasSuffix(" -rF") })
        }
    }

    @Test("--theme completes bundled and custom ids, read when Tab is pressed")
    func themeIDs() throws {
        let folder = try TempFolder()
        try folder.file("Mine.css", Self.theme)
        try folder.file("broken.css", "@import url(\"other.css\");\n")
        let environment = [ThemeResolver.themesFolderVariable: folder.url.path]
        let ids = ThemeFlavorOptions.completionThemeIDs(shell: .bash, environment: environment)
        #expect(ids == ["github", "document", "serif", "custom:Mine.css"])
        // zsh's `_describe` would read the colon as the start of a description.
        let zsh = ThemeFlavorOptions.completionThemeIDs(shell: .zsh, environment: environment)
        #expect(zsh.last == #"custom\:Mine.css"#)
    }

    @Test(
        "the binary answers the scripts' --theme completion request",
        arguments: [("zsh", #"custom\:Mine.css"#), ("bash", "custom:Mine.css"), ("fish", "custom:Mine.css")])
    func themeRequest(shell: String, custom: String) throws {
        let folder = try TempFolder()
        try folder.file("Mine.css", Self.theme)
        // What the generated scripts run: `peep ---completion -- --theme <word index> <cursor> <words…>`.
        let result = try #require(
            try CLIBinary.run(
                ["---completion", "--", "--theme", "2", "0", "peep", "--theme", ""], themesFolder: folder.url,
                environment: ["SAP_SHELL": shell]))
        #expect(result.status == 0)
        let lines = result.stdout.components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        #expect(lines == ["github", "document", "serif", custom])
    }

    @Test("--flavor completes the bundled flavor ids")
    func flavorIDs() throws {
        let script = try CompletionScript.script(for: .zsh)
        #expect(script.contains("___flavor=('gfm' 'commonmark')"))
    }

    @Test("make cli-docs wrote a script for each shell", .enabled(if: GeneratedCLIDocs.isAvailable))
    func generatedScripts() throws {
        #expect(try GeneratedCLIDocs.contents("completions/_peep").hasPrefix("#compdef peep"))
        #expect(try GeneratedCLIDocs.contents("completions/peep.bash").contains("complete -o filenames -F _peep peep"))
        #expect(try GeneratedCLIDocs.contents("completions/peep.fish").contains("complete -c 'peep'"))
        for (file, shell) in [("_peep", CompletionShell.zsh), ("peep.bash", .bash), ("peep.fish", .fish)] {
            #expect(try GeneratedCLIDocs.contents("completions/" + file) == CompletionScript.script(for: shell) + "\n")
        }
    }

    // MARK: - ArgumentParser's help subcommand (0.1.0 shipped a zsh script zsh refused)

    @Test(
        "the binary prints CompletionScript's script, as make cli-docs and the app bundle use",
        arguments: ["zsh", "bash", "fish"])
    func binaryScript(shell: String) throws {
        let completionShell = try #require(CompletionShell(rawValue: shell))
        let result = try #require(try CLIBinary.run(["--generate-completion-script", shell]))
        #expect(result.status == 0)
        #expect(result.stdout == (try CompletionScript.script(for: completionShell)) + "\n")
    }

    @Test("no script offers ArgumentParser's help subcommand")
    func noHelpSubcommand() throws {
        let zsh = try CompletionScript.script(for: .zsh)
        #expect(!zsh.contains("->command") && !zsh.contains("->arg"))
        // One rest argument in `_peep`'s specs: zsh refuses a second ("doubled rest argument
        // definition"). The `_peep_help` that follows is ArgumentParser's, now never called.
        let peep = try #require(zsh.components(separatedBy: "\n_peep_help() {").first)
        let rest = peep.components(separatedBy: "\n").filter {
            $0.hasPrefix("        '*:") || $0.hasPrefix("        '(-)*")
        }
        #expect(rest == ["        '*:FILE:_files'"])
        let fish = try CompletionScript.script(for: .fish)
        #expect(!fish.contains("-fa 'help'") && !fish.contains("case 'help'") && !fish.contains("\"peep help\""))
    }

    @Test("each line CompletionScript removes is in ArgumentParser's script exactly once")
    func removalsMatchOnce() {
        for shell in [CompletionShell.zsh, .fish] {
            let script = PeepCommand.completionScript(for: shell) + "\n"
            for lines in CompletionScript.removals(for: shell) {
                let matches = script.components(separatedBy: "\n" + lines + "\n").count - 1
                #expect(matches == 1, "\(shell.rawValue): \(lines)")
            }
        }
        #expect(CompletionScript.removals(for: .bash).isEmpty)
    }

    @Test("zsh completes flags, --flavor's ids, and files in a real shell, without errors")
    func zshCompletes() throws {
        let folder = try TempFolder()
        try folder.file("notes.md", "# Notes\n")
        let script = try #require(try CLIBinary.run(["--generate-completion-script", "zsh"])).stdout

        let flag = try ShellCompletion.zsh("peep --fla", script: script, in: folder.url)
        #expect(flag.candidates == ["--flavor"])
        let flavor = try ShellCompletion.zsh("peep --flavor ", script: script, in: folder.url)
        #expect(flavor.candidates == ["gfm", "commonmark"])
        let file = try ShellCompletion.zsh("peep notes.md ", script: script, in: folder.url)
        #expect(file.candidates == ["notes.md"])
        for completion in [flag, flavor, file] {
            #expect(!completion.output.contains("doubled rest argument"), "\(completion.output)")
            #expect(!completion.output.contains("_arguments:"), "\(completion.output)")
        }
    }

    @Test("bash completes flags, --flavor's ids, and files in a real shell, without help")
    func bashCompletes() throws {
        let folder = try TempFolder()
        try folder.file("notes.md", "# Notes\n")
        let script = try #require(try CLIBinary.run(["--generate-completion-script", "bash"])).stdout

        #expect(try ShellCompletion.bash("peep --fla", script: script, in: folder.url).candidates == ["--flavor"])
        let flavor = try ShellCompletion.bash("peep --flavor ", script: script, in: folder.url)
        #expect(flavor.candidates == ["gfm", "commonmark"])
        let file = try ShellCompletion.bash("peep notes.md ", script: script, in: folder.url)
        #expect(file.candidates == ["notes.md"])
        #expect(try ShellCompletion.bash("peep notes.md h", script: script, in: folder.url).candidates.isEmpty)
    }
}
