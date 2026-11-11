import Foundation
import Testing

/// `mdv`'s arguments as ArgumentParser describes them (`--experimental-dump-help`, the JSON
/// generate-manual reads), so tests cover every flag without a hand-kept list (#71).
struct CommandOptions {
    struct Argument: Decodable {
        let kind: String
        let shouldDisplay: Bool
        let names: [ArgumentName]?
        let valueName: String?

        /// `-o`, `--output`: each spelling a reader can type.
        var spellings: [String] {
            (names ?? []).map { $0.kind == "short" ? "-" + $0.name : "--" + $0.name }
        }
    }

    private struct ToolInfo: Decodable {
        let command: DumpedCommand
    }

    /// The arguments `mdv --help` shows (hidden ones excluded).
    let visible: [Argument]

    /// Reads them from the built binary. Records an issue and returns nil when it can't.
    static func load() throws -> CommandOptions? {
        guard let result = try CLIBinary.run(["--experimental-dump-help"]), result.status == 0 else {
            Issue.record("mdv --experimental-dump-help failed")
            return nil
        }
        let info = try JSONDecoder().decode(ToolInfo.self, from: result.standardOutput)
        return CommandOptions(visible: (info.command.arguments ?? []).filter(\.shouldDisplay))
    }

    /// The flags and options (not positional arguments).
    var options: [Argument] {
        visible.filter { $0.kind != "positional" }
    }
}

struct ArgumentName: Decodable {
    let kind: String
    let name: String
}

struct DumpedCommand: Decodable {
    let arguments: [CommandOptions.Argument]?
}

/// The folder `make cli-docs` generated into, passed to `make test-core` as `MDV_CLI_DOCS`.
/// Plain `swift test` doesn't generate it, and the tests that read it are skipped.
enum GeneratedCLIDocs {
    static var folder: URL? {
        guard let path = ProcessInfo.processInfo.environment["MDV_CLI_DOCS"], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static var isAvailable: Bool { folder != nil }

    static func contents(_ path: String) throws -> String {
        let folder = try #require(folder)
        return try String(contentsOf: folder.appending(path: path), encoding: .utf8)
    }
}
