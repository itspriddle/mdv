import ArgumentParser
import Foundation
import MdvCore

@main
struct MdvCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mdv",
        abstract: "View Markdown files.",
        discussion: """
            Opens FILE(s) in mdv. With no FILE, reads Markdown from standard input.

              mdv README.md
              echo '# Markdown' | mdv
              mdv --html README.md > README.html
            """,
        version: MdvInfo.version
    )

    /// Placeholder until the final name is chosen; must match `PRODUCT_BUNDLE_IDENTIFIER_BASE`.
    static let appBundleIdentifier = "com.itspriddle.mdv"

    @Flag(name: .long, help: "Print rendered HTML to standard output instead of opening the app.")
    var html = false

    @Argument(help: "Markdown files to view. Reads standard input when omitted.")
    var files: [String] = []

    func run() throws {
        if html {
            try printHTML()
        } else {
            try openInApp()
        }
    }

    private func printHTML() throws {
        let renderer = HTMLRenderer()
        let sources: [(title: String, markdown: String)] =
            files.isEmpty
            ? [("stdin", try readStandardInput())]
            : try files.map { path in
                let url = URL(fileURLWithPath: path)
                return (url.lastPathComponent, try String(contentsOf: url, encoding: .utf8))
            }
        for source in sources {
            let rendered = renderer.render(source.markdown)
            let document = HTMLDocument(title: rendered.title ?? source.title, body: rendered.html)
            print(document.html)
        }
    }

    private func openInApp() throws {
        var paths = files
        if paths.isEmpty {
            // Proper stdin handling (no temp file, live updates) is planned for M5.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("mdv-stdin-\(UUID().uuidString).md")
            try readStandardInput().write(to: url, atomically: true, encoding: .utf8)
            paths = [url.path]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", Self.appBundleIdentifier, "--"] + paths
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw ExitCode(process.terminationStatus)
        }
    }

    private func readStandardInput() throws -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw ValidationError("Standard input is not valid UTF-8.")
        }
        return text
    }
}
