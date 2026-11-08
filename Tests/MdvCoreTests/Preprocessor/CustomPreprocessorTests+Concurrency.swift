import Darwin
import Foundation
import Testing

@testable import MdvCore

/// Cancellation, the cooperative pool, and leaks under concurrent runs (#56).
extension CustomPreprocessorTests {
    @Test("cancelling a run stops the script and throws CancellationError")
    func cancelRunning() async throws {
        let fixtures = try PreprocessorFixtures()
        let pidFile = fixtures.pidFile()
        var limits = PreprocessorFixtures.shortLimits
        limits.timeout = .seconds(30)
        let preprocessor = try fixtures.preprocessor("hang", arguments: [pidFile], limits: limits)
        let task = Task { try await preprocessor.run(input: PreprocessorFixtures.document, documentURL: nil) }
        let pid = try #require(try await PreprocessorFixtures.pids(in: pidFile).first)

        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(start.duration(to: .now) < .seconds(2))
        #expect(try await PreprocessorFixtures.processesGone(group: pid, pids: [pid]))
        #expect(PreprocessorDescriptors.openCount == 0)
    }

    @Test("a task cancelled before the run starts never launches the script")
    func cancelBeforeStart() async throws {
        let fixtures = try PreprocessorFixtures()
        let pidFile = fixtures.pidFile()
        let preprocessor = try fixtures.preprocessor("sleep", arguments: [pidFile])
        let task = Task {
            try? await Task.sleep(for: .seconds(30))
            return try await preprocessor.run(input: PreprocessorFixtures.document, documentURL: nil)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: pidFile))
        #expect(PreprocessorDescriptors.openCount == 0)
    }

    @Test("runs in flight don't hold cooperative threads")
    func doesNotBlockCooperativePool() async throws {
        let fixtures = try PreprocessorFixtures()
        var limits = PreprocessorFixtures.shortLimits
        limits.timeout = .seconds(1)
        let preprocessor = try fixtures.preprocessor("sleep", arguments: ["/dev/null"], limits: limits)
        let runs = 4 * ProcessInfo.processInfo.activeProcessorCount
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<runs {
                group.addTask {
                    _ = try? await preprocessor.run(input: PreprocessorFixtures.document, documentURL: nil)
                }
            }
            // Every run is now sleeping in its script; a blocked pool couldn't start this.
            try await Task.sleep(for: .milliseconds(200))
            let start = ContinuousClock.now
            _ = await Task.detached { 1 }.value
            #expect(start.duration(to: .now) < .milliseconds(300))
            try await group.waitForAll()
        }
        #expect(PreprocessorDescriptors.openCount == 0)
    }

    @Test("every misbehavior at once leaves no process or descriptor behind")
    func concurrentMisbehaviorLeavesNothing() async throws {
        let fixtures = try PreprocessorFixtures()
        let pidFiles = (0..<3).map { _ in fixtures.pidFile() }
        let runs: [(String, [String])] = [
            ("hang", [pidFiles[0]]), ("sleep", [pidFiles[1]]), ("fork-child", [pidFiles[2]]),
            ("huge-output", []), ("crash", []), ("fail", []), ("invalid-utf8", []), ("nul", []),
            ("close-stdout", []), ("trickle", []), ("stderr-flood", []), ("ignore-stdin", []), ("upcase", []),
        ]
        let preprocessors = try runs.map { try fixtures.preprocessor($0.0, arguments: $0.1) }
        let input = Data(repeating: UInt8(ascii: "a"), count: 1024 * 1024)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                for preprocessor in preprocessors {
                    group.addTask { _ = try? await preprocessor.run(input: input, documentURL: nil) }
                }
            }
        }
        #expect(PreprocessorDescriptors.openCount == 0)
        for pidFile in pidFiles {
            // Each fixture appends nothing: the last run's pids are in the file.
            let pids = try await PreprocessorFixtures.pids(in: pidFile)
            let group = try #require(pids.first)
            #expect(try await PreprocessorFixtures.processesGone(group: group, pids: pids))
        }
        #expect(try Self.childProcessCount() == 0)
    }

    /// The test process's own live children (zombies included): the runner reaps each script.
    static func childProcessCount() throws -> Int {
        var count: Int32 = 0
        var pids = [pid_t](repeating: 0, count: 1024)
        count = proc_listchildpids(getpid(), &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        try #require(count >= 0)
        return Int(count)
    }
}
