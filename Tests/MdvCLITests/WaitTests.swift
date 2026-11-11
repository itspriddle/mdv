import Darwin
import Foundation
import MdvCore
import Testing

@testable import MdvCLIKit

/// `mdv --wait` (#69): the flag's rules, and `WindowsClosedWaiter`, which ends on the app's
/// notification for its token or the app's process exiting.
@Suite("Waiting for windows", .timeLimit(.minutes(1)))
struct WaitTests {
    @Test("--wait reaches the opener; without it, the opener doesn't wait")
    func flag() async throws {
        let folder = try TempFolder()
        let file = try folder.file("a.md", "# A")
        let waiting = RecordingAppOpener()
        #expect(await CLIHarness.run(["--wait", file], appOpener: waiting).status == 0)
        #expect(waiting.waits == [true])
        let plain = RecordingAppOpener()
        #expect(await CLIHarness.run([file], appOpener: plain).status == 0)
        #expect(plain.waits == [false])
    }

    @Test(
        "--wait with HTML output or a list is a usage error",
        arguments: [["--html"], ["--fragment"], ["-o", "out.html"], ["--list-themes"]])
    func usage(flags: [String]) async throws {
        let folder = try TempFolder()
        let file = try folder.file("a.md", "# A")
        let arguments = flags.first == "--list-themes" ? ["--wait"] + flags : ["--wait"] + flags + [file]
        let opener = RecordingAppOpener()
        let result = await CLIHarness.run(arguments, appOpener: opener)
        #expect(result.status == 64)
        #expect(result.stderr.contains("--wait"), "\(result.stderr)")
        #expect(opener.requests.isEmpty)
    }

    @Test("each waiter has its own token")
    func tokens() throws {
        #expect(try WindowsClosedWaiter().token != WindowsClosedWaiter().token)
    }

    @Test("the notification for the token ends the wait; another token's doesn't")
    func notification() async throws {
        let waiter = try WindowsClosedWaiter()
        let task = Task { await waiter.wait(forProcess: nil) }
        DarwinNotificationRegistration.post(AppOpenEvent.windowsClosedNotificationName(for: UUID()))
        try await Task.sleep(for: .milliseconds(300))
        #expect(!waiter.isFinished)
        DarwinNotificationRegistration.post(AppOpenEvent.windowsClosedNotificationName(for: waiter.token))
        await task.value
        #expect(waiter.isFinished)
    }

    @Test("a notification posted before the wait starts still ends it")
    func early() async throws {
        let waiter = try WindowsClosedWaiter()
        DarwinNotificationRegistration.post(AppOpenEvent.windowsClosedNotificationName(for: waiter.token))
        try await Task.sleep(for: .milliseconds(100))
        await waiter.wait(forProcess: nil)
        #expect(waiter.isFinished)
    }

    @Test("the app's process exiting ends the wait")
    func processExit() async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        let waiter = try WindowsClosedWaiter()
        let task = Task { await waiter.wait(forProcess: process.processIdentifier) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(!waiter.isFinished)
        kill(process.processIdentifier, SIGKILL)
        await task.value
        #expect(waiter.isFinished)
    }

    @Test("a process that is already gone ends the wait at once")
    func goneProcess() async throws {
        let exited = AsyncStream<Void>.makeStream()
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/true")
        process.terminationHandler = { _ in exited.continuation.finish() }
        try process.run()
        for await _ in exited.stream {}
        let waiter = try WindowsClosedWaiter()
        await waiter.wait(forProcess: process.processIdentifier)
        #expect(waiter.isFinished)
    }

    @Test("cancelling the task ends the wait")
    func cancel() async throws {
        let waiter = try WindowsClosedWaiter()
        let task = Task { await waiter.wait(forProcess: nil) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await task.value
        #expect(waiter.isFinished)
    }
}
