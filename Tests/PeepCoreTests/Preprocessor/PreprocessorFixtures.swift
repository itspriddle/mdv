import Darwin
import Foundation
import Testing

@testable import PeepCore

/// The fixture scripts in `Fixtures/preprocessors`, copied into a temporary folder (with
/// their executable bit set, which a resource copy needn't keep) so tests also have a
/// scratch place for pid files and documents.
struct PreprocessorFixtures: ~Copyable {
    /// Short limits so misbehaving scripts cost a fraction of a second each.
    static let shortLimits = PreprocessorLimits(
        timeout: .milliseconds(400),
        terminationGracePeriod: .milliseconds(100),
        maximumInputBytes: 16 * 1024 * 1024,
        maximumOutputBytes: 64 * 1024,
        maximumErrorBytes: 1024
    )

    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-preprocessor-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The path of fixture `name` (without `.sh`), copied and made executable.
    func script(_ name: String) throws -> String {
        let source = try #require(
            Bundle.module.url(forResource: name, withExtension: "sh", subdirectory: "Fixtures/preprocessors"))
        let destination = folder.appending(path: "\(name).sh")
        if !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        }
        return destination.path(percentEncoded: false)
    }

    func preprocessor(
        _ name: String, arguments: [String] = [], limits: PreprocessorLimits = shortLimits
    ) throws -> CustomPreprocessor {
        let configuration = try PreprocessorConfiguration(
            executablePath: try script(name), arguments: arguments, limits: limits)
        return CustomPreprocessor(configuration: configuration)
    }

    /// A preprocessor running fixture `name` through `record-pid`, which appends the run's pid
    /// to `pidLog` before becoming the fixture.
    func preprocessor(
        _ name: String, arguments: [String] = [], recordingPIDsTo pidLog: String,
        limits: PreprocessorLimits = shortLimits
    ) throws -> CustomPreprocessor {
        try preprocessor("record-pid", arguments: [pidLog, try script(name)] + arguments, limits: limits)
    }

    /// A fresh path in the folder for a script to write pids to.
    func pidFile() -> String {
        folder.appending(path: "pids-\(UUID().uuidString)").path(percentEncoded: false)
    }

    /// The pids a script wrote to `path`, waiting briefly for it to appear.
    static func pids(in path: String) async throws -> [pid_t] {
        for _ in 0..<200 {
            if let text = try? String(contentsOfFile: path, encoding: .utf8), text.hasSuffix("\n") {
                return text.split(whereSeparator: \.isWhitespace).compactMap { pid_t($0) }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("no pid file at \(path)")
        return []
    }

    /// Whether every process in group `group` (the script's pid) and `pids` is gone, waiting
    /// up to 2 s for launchd to reap orphans the runner killed.
    static func processesGone(group: pid_t, pids: [pid_t]) async throws -> Bool {
        for _ in 0..<200 {
            let groupGone = killpg(group, 0) != 0 && errno == ESRCH
            let pidsGone = pids.allSatisfy { kill($0, 0) != 0 && errno == ESRCH }
            if groupGone, pidsGone { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    static let document = Data("# Title\n\nSome *text*.\n".utf8)
}

extension PreprocessorError.Reason {
    /// The case without its payload, for comparing reasons whose payload a test can't predict.
    var kind: String {
        String(describing: self).prefix { $0 != "(" }.description
    }
}
