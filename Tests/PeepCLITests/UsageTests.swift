import MdvCLIKit
import Testing

@Suite("Usage and help")
struct UsageTests {
    @Test("an unknown flag exits 64 with ArgumentParser's message")
    func unknownFlag() async {
        let result = await CLIHarness.run(["--bogus"])
        #expect(result.status == ExitStatus.usage)
        #expect(result.status == 64)
        #expect(result.stderr.contains("Unknown option '--bogus'"))
    }

    @Test("--help documents every output flag and every exit status")
    func help() {
        let help = MdvCommand.helpMessage(columns: 100)
        for flag in ["--html", "--fragment", "-o, --output <FILE>", "[<FILE> ...]"] {
            #expect(help.contains(flag), "\(flag)")
        }
        for status in [
            ExitStatus.success, ExitStatus.usage, ExitStatus.dataError, ExitStatus.noInput,
            ExitStatus.unavailable, ExitStatus.cannotCreate, ExitStatus.ioError,
        ] {
            #expect(help.contains("\n  \(status) "), "exit status \(status)")
        }
    }

    @Test("--version prints the version")
    func version() async {
        let result = await CLIHarness.run(["--version"])
        #expect(result.status == 0)
    }
}
