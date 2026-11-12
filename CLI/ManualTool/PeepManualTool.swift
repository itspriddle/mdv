// A build tool, not shipped: `make man` runs ArgumentParser's generate-manual plugin on `peep`,
// then this, which adds Peep's hand-written sections (`ManualPage`, #71).
import ArgumentParser
import Foundation
import PeepCLIKit

@main
struct PeepManualTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "peep-manual",
        abstract: "Finish generate-manual's peep.1 with Peep's hand-written sections.")

    @Argument(help: "The peep.1 that generate-manual wrote.")
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
