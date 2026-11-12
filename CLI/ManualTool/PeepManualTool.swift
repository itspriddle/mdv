// A build tool, not shipped: `make man` runs ArgumentParser's generate-manual plugin on `mdv`,
// then this, which adds mdv's hand-written sections (`ManualPage`, #71).
import ArgumentParser
import Foundation
import MdvCLIKit

@main
struct MdvManualTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mdv-manual",
        abstract: "Finish generate-manual's mdv.1 with mdv's hand-written sections.")

    @Argument(help: "The mdv.1 that generate-manual wrote.")
    var generated: String

    @Option(name: .shortAndLong, help: "Where to write the finished page.")
    var output: String

    func run() throws {
        let source = try String(contentsOfFile: generated, encoding: .utf8)
        let page: String
        do {
            page = try ManualPage.finish(source)
        } catch {
            throw ValidationError("\(generated): \(error.description)")
        }
        try Data(page.utf8).write(to: URL(fileURLWithPath: output), options: .atomic)
    }
}
