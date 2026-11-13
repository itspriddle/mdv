import Foundation
import Testing

/// Completes a `peep` command line in a real shell with a generated script, as pressing Tab
/// would: zsh's completion system in a pseudo-terminal (`Fixtures/completions/complete.zsh`) or
/// bash's completion function (`complete.bash`). Neither reads the reader's shell setup.
struct ShellCompletion {
    /// Each candidate the shell would offer, in order.
    let candidates: [String]
    /// Everything the shell wrote, including its own errors.
    let output: String

    /// Completes `line` (ending in a space for a new word) with `script` installed as zsh's
    /// `_peep`, in `directory` (file names come from there). HOME is an empty folder.
    static func zsh(_ line: String, script: String, in directory: URL) throws -> ShellCompletion {
        let scratch = try TempFolder()
        let home = scratch.url.appending(path: "home", directoryHint: .isDirectory)
        let functions = scratch.url.appending(path: "functions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: functions, withIntermediateDirectories: true)
        try script.write(to: functions.appending(path: "_peep"), atomically: true, encoding: .utf8)
        let arguments = ["-f", try driver("complete.zsh"), functions.path, home.path, line]
        return try withExtendedLifetime(scratch) { try run("/bin/zsh", arguments, in: directory) }
    }

    /// Completes `line` with `script` sourced into bash, in `directory`.
    static func bash(_ line: String, script: String, in directory: URL) throws -> ShellCompletion {
        let scratch = try TempFolder()
        let file = try scratch.file("peep.bash", script)
        let arguments = ["--norc", "--noprofile", try driver("complete.bash"), file, line]
        return try withExtendedLifetime(scratch) { try run("/bin/bash", arguments, in: directory) }
    }

    private static func driver(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/completions")
        return try #require(url).path
    }

    private static func run(_ shell: String, _ arguments: [String], in directory: URL) throws -> ShellCompletion {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // Only what the shells need; nothing from the reader's environment reaches them.
        process.environment = ["PATH": "/usr/bin:/bin", "TERM": "dumb", "LANG": "en_US.UTF-8"]
        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        let output = String(bytes: data, encoding: .utf8) ?? "<not UTF-8>"
        #expect(process.terminationStatus == 0, "\(shell) completion driver failed:\n\(output)")
        // zsh's line editor puts escape sequences before a line; the marker still ends it.
        let candidates = output.components(separatedBy: .newlines).compactMap { line in
            line.range(of: "MATCH:").map { String(line[$0.upperBound...]) }
        }
        return ShellCompletion(candidates: candidates, output: output)
    }
}
