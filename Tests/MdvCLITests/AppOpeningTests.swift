import Foundation
import MdvCLIKit
import Testing

@Suite("Opening in the app")
struct AppOpeningTests {
    @Test("FILEs without an output flag go to the app as absolute URLs, in order")
    func files() async throws {
        let folder = try TempFolder()
        let opener = RecordingAppOpener()
        let result = await CLIHarness.run(["b.md", folder.path("a.md")], appOpener: opener)
        #expect(result.status == 0)
        #expect(result.stdout.isEmpty)
        let cwd = FileManager.default.currentDirectoryPath
        #expect(
            result.openedInApp == [
                AppOpenRequest(files: [
                    URL(fileURLWithPath: "\(cwd)/b.md"), URL(fileURLWithPath: folder.path("a.md")),
                ])
            ])
    }

    @Test("standard input goes to the app as text")
    func standardInput() async {
        let result = await CLIHarness.run([], stdin: Data("# Piped\n".utf8))
        #expect(result.status == 0)
        #expect(result.openedInApp == [AppOpenRequest(files: [], standardInput: "# Piped\n")])
    }

    @Test("standard input that isn't UTF-8 never reaches the app")
    func invalidStandardInput() async {
        let result = await CLIHarness.run([], stdin: Data([0xFF]))
        #expect(result.status == 65)
        #expect(result.openedInApp.isEmpty)
    }

    @Test("an opener failure is reported with its status")
    func failure() async {
        let opener = RecordingAppOpener(
            failingWith: CLIError("couldn't open the app", status: ExitStatus.unavailable))
        let result = await CLIHarness.run(["a.md"], appOpener: opener)
        #expect(result.status == 69)
        #expect(result.stderr == "mdv: couldn't open the app\n")
    }
}
