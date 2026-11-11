import ArgumentParser
import Foundation
import Testing

@testable import MdvCLIKit

/// Shell completions (#71): ArgumentParser's scripts, plus `--theme`'s dynamic ids.
@Suite("Shell completions")
struct CompletionTests {
    private static let shells: [CompletionShell] = [.zsh, .bash, .fish]
    private static let theme = "/* mdv-theme\n   name: Test Theme\n*/\nbody { color: #123456; }\n"

    @Test("each shell's script offers every option of MdvCommand", arguments: shells)
    func everyOption(shell: CompletionShell) throws {
        let script = MdvCommand.completionScript(for: shell)
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
    func files(shell: CompletionShell) {
        let script = MdvCommand.completionScript(for: shell)
        let lines = script.components(separatedBy: "\n")
        switch shell {
        case .zsh:
            #expect(lines.contains { $0.contains("'*:FILE:_files'") })
            #expect(lines.contains { $0.contains("--output}'[") && $0.hasSuffix(":FILE:_files'") })
            #expect(lines.contains { $0.contains("'--preprocessor[") && $0.hasSuffix(":PATH:_files'") })
        case .bash:
            // The positional case, --output's, and --preprocessor's.
            #expect(lines.filter { $0.contains("__mdv_add_completions -f") }.count == 3)
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
        // What the generated scripts run: `mdv ---completion -- --theme <word index> <cursor> <words…>`.
        let result = try #require(
            try CLIBinary.run(
                ["---completion", "--", "--theme", "2", "0", "mdv", "--theme", ""], themesFolder: folder.url,
                environment: ["SAP_SHELL": shell]))
        #expect(result.status == 0)
        let lines = result.stdout.components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        #expect(lines == ["github", "document", "serif", custom])
    }

    @Test("--flavor completes the bundled flavor ids")
    func flavorIDs() {
        let script = MdvCommand.completionScript(for: .zsh)
        #expect(script.contains("___flavor=('gfm' 'commonmark')"))
    }

    @Test("make cli-docs wrote a script for each shell", .enabled(if: GeneratedCLIDocs.isAvailable))
    func generatedScripts() throws {
        #expect(try GeneratedCLIDocs.contents("completions/_mdv").hasPrefix("#compdef mdv"))
        #expect(try GeneratedCLIDocs.contents("completions/mdv.bash").contains("complete -o filenames -F _mdv mdv"))
        #expect(try GeneratedCLIDocs.contents("completions/mdv.fish").contains("complete -c 'mdv'"))
    }
}
