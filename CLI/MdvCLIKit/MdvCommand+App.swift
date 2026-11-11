import Foundation

// `mdv FILE...` and `cmd | mdv`: open documents in the app (#67, #68).

extension MdvCommand {
    func openInApp(in environment: CLIEnvironment) async throws(CLIError) {
        var files: [URL] = []
        var standardInput: String?
        for source in input.sources {
            switch source {
            case .file:
                if let url = source.url { files.append(url) }
            case .standardInput:
                standardInput = try InputDocument.read(source, in: environment).markdown
            }
        }
        let request = AppOpenRequest(files: files, standardInput: standardInput)
        try await environment.appOpener.open(request, options: app)
    }
}
