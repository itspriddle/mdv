import Darwin
import Foundation
import Testing

@testable import MdvCore

/// Scripts that misbehave (#56's acceptance criteria): each yields a typed error within the
/// limits, leaves no process behind, and leaves no descriptor open.
extension CustomPreprocessorTests {
    /// Runs fixture `name` expecting a `PreprocessorError`, and checks the limits held: it
    /// returned within `timeout` plus the grace period (with slack), and no descriptor is open.
    private func expectFailure(
        _ fixtures: borrowing PreprocessorFixtures,
        _ name: String,
        arguments: [String] = [],
        input: Data = PreprocessorFixtures.document,
        limits: PreprocessorLimits = PreprocessorFixtures.shortLimits
    ) async throws -> PreprocessorError? {
        let preprocessor = try fixtures.preprocessor(name, arguments: arguments, limits: limits)
        let start = ContinuousClock.now
        let error = await #expect(throws: PreprocessorError.self) {
            try await preprocessor.run(input: input, documentURL: nil)
        }
        #expect(start.duration(to: .now) < limits.timeout + limits.terminationGracePeriod + .seconds(1))
        #expect(PreprocessorDescriptors.openCount == 0)
        return error
    }

    @Test("a script that hangs and ignores SIGTERM times out and is killed")
    func hang() async throws {
        let fixtures = try PreprocessorFixtures()
        let pidFile = fixtures.pidFile()
        let error = try await expectFailure(fixtures, "hang", arguments: [pidFile])
        #expect(error?.reason == .timedOut(PreprocessorFixtures.shortLimits.timeout))
        let pid = try #require(try await PreprocessorFixtures.pids(in: pidFile).first)
        #expect(try await PreprocessorFixtures.processesGone(group: pid, pids: [pid]))
    }

    @Test("a script that sleeps past the timeout is stopped by SIGTERM")
    func sleepPastTimeout() async throws {
        let fixtures = try PreprocessorFixtures()
        let pidFile = fixtures.pidFile()
        let error = try await expectFailure(fixtures, "sleep", arguments: [pidFile])
        #expect(error?.reason == .timedOut(PreprocessorFixtures.shortLimits.timeout))
        #expect(error?.message == "The preprocessor didn’t finish within 0.4 seconds.")
        let pid = try #require(try await PreprocessorFixtures.pids(in: pidFile).first)
        #expect(try await PreprocessorFixtures.processesGone(group: pid, pids: [pid]))
    }

    @Test("a child that hangs dies with its script")
    func forkedChildHangs() async throws {
        let fixtures = try PreprocessorFixtures()
        let pidFile = fixtures.pidFile()
        let error = try await expectFailure(fixtures, "fork-child", arguments: [pidFile])
        #expect(error?.reason == .timedOut(PreprocessorFixtures.shortLimits.timeout))
        let pids = try await PreprocessorFixtures.pids(in: pidFile)
        #expect(pids.count == 2)
        let group = try #require(pids.first)
        #expect(try await PreprocessorFixtures.processesGone(group: group, pids: pids))
    }

    @Test("a child left behind by a script that succeeded is killed, and the output kept")
    func forkedChildOutlivesScript() async throws {
        let fixtures = try PreprocessorFixtures()
        let pidFile = fixtures.pidFile()
        let limits = PreprocessorFixtures.shortLimits
        let start = ContinuousClock.now
        let output = try await fixtures.preprocessor("fork-child", arguments: [pidFile, "exit"], limits: limits)
            .run(input: PreprocessorFixtures.document, documentURL: nil)
        #expect(output == "done\n")
        // The child ignores SIGTERM and holds stdout open, so the run waits out the grace
        // period (then SIGKILL), not the timeout.
        let elapsed = start.duration(to: .now)
        #expect(elapsed >= limits.terminationGracePeriod)
        #expect(elapsed < limits.timeout)
        let pids = try await PreprocessorFixtures.pids(in: pidFile)
        let group = try #require(pids.first)
        #expect(try await PreprocessorFixtures.processesGone(group: group, pids: pids))
        #expect(PreprocessorDescriptors.openCount == 0)
    }

    @Test("huge output stops the script at the output limit")
    func hugeOutput() async throws {
        let fixtures = try PreprocessorFixtures()
        let error = try await expectFailure(fixtures, "huge-output")
        #expect(error?.reason == .outputTooLarge(limit: PreprocessorFixtures.shortLimits.maximumOutputBytes))
    }

    @Test("a script that never reads a large document still answers")
    func neverReadsStdin() async throws {
        let fixtures = try PreprocessorFixtures()
        let input = Data(repeating: UInt8(ascii: "a"), count: 8 * 1024 * 1024)
        var limits = PreprocessorFixtures.shortLimits
        limits.timeout = .seconds(5)
        let output = try await fixtures.preprocessor("ignore-stdin", limits: limits).run(input: input, documentURL: nil)
        #expect(output == "ignored stdin\n")
        #expect(PreprocessorDescriptors.openCount == 0)
    }

    @Test("a script that closes stdin doesn't raise SIGPIPE in mdv")
    func closesStdin() async throws {
        let fixtures = try PreprocessorFixtures()
        let input = Data(repeating: UInt8(ascii: "a"), count: 1024 * 1024)
        var limits = PreprocessorFixtures.shortLimits
        limits.timeout = .seconds(5)
        let output = try await fixtures.preprocessor("close-stdin", limits: limits).run(input: input, documentURL: nil)
        #expect(output == "closed stdin\n")
    }

    @Test("a crash by signal is reported with the signal and stderr")
    func crashBySignal() async throws {
        let fixtures = try PreprocessorFixtures()
        let error = try await expectFailure(fixtures, "crash")
        #expect(error?.reason == .signaled(SIGSEGV))
        #expect(error?.standardError == "about to crash\n")
        #expect(error?.message.hasPrefix("The preprocessor was stopped by signal 11") == true)
    }

    @Test("a non-zero exit is reported with the status and stderr, and the output dropped")
    func nonZeroExit() async throws {
        let fixtures = try PreprocessorFixtures()
        let error = try await expectFailure(fixtures, "fail")
        #expect(error?.reason == .exited(status: 3))
        #expect(error?.standardError == "something went wrong\n")
        #expect(error?.description == "The preprocessor exited with status 3.\nsomething went wrong\n")
    }

    @Test("stderr keeps only its tail")
    func stderrTail() async throws {
        let fixtures = try PreprocessorFixtures()
        let error = try await expectFailure(fixtures, "stderr-flood")
        #expect(error?.reason == .exited(status: 1))
        let tail = error?.standardError ?? ""
        #expect(tail.utf8.count <= PreprocessorFixtures.shortLimits.maximumErrorBytes)
        #expect(tail.hasSuffix("noise line 3999 of the stderr flood\nthe last line\n"))
    }

    @Test("invalid UTF-8 output is an error")
    func invalidUTF8() async throws {
        let fixtures = try PreprocessorFixtures()
        let error = try await expectFailure(fixtures, "invalid-utf8")
        #expect(error?.reason == .outputNotUTF8)
    }

    @Test("a NUL byte in the output is an error")
    func nulByte() async throws {
        let fixtures = try PreprocessorFixtures()
        let error = try await expectFailure(fixtures, "nul")
        #expect(error?.reason == .outputContainsNUL)
    }

    @Test("a script that closes stdout early and keeps running times out")
    func closesStdoutAndHangs() async throws {
        let fixtures = try PreprocessorFixtures()
        let error = try await expectFailure(fixtures, "close-stdout")
        #expect(error?.reason == .timedOut(PreprocessorFixtures.shortLimits.timeout))
    }

    @Test("a script that closes stdout early and exits 0 returns what it wrote")
    func closesStdoutAndExits() async throws {
        let fixtures = try PreprocessorFixtures()
        let output = try await fixtures.preprocessor("close-stdout", arguments: ["exit"])
            .run(input: PreprocessorFixtures.document, documentURL: nil)
        #expect(output == "partial")
    }

    @Test("output that trickles forever times out")
    func trickle() async throws {
        let fixtures = try PreprocessorFixtures()
        let error = try await expectFailure(fixtures, "trickle")
        #expect(error?.reason == .timedOut(PreprocessorFixtures.shortLimits.timeout))
    }
}
