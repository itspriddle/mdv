import Foundation

// `peep FILE...` and `cmd | peep`: open documents in the app (#67, #68).

extension PeepCommand {
    /// Checks every input and `--theme` first, so a bad path or theme opens nothing; then hands
    /// the request to `environment.appOpener`.
    func openInApp(in environment: CLIEnvironment) async throws(CLIError) {
        var files: [URL] = []
        var standardInput: String?
        for source in input.sources {
            switch source {
            case .file(let path):
                try Self.checkReadableFile(atPath: path)
                if let url = source.url { files.append(url) }
            case .standardInput:
                standardInput = try InputDocument.readForWindow(in: environment).markdown
            }
        }
        let request = AppOpenRequest(
            files: files, standardInput: standardInput, themeID: try windowThemeID(in: environment))
        try await environment.appOpener.open(request, options: app)
    }

    /// `--theme` as the windows' pick: the resolved theme's id (bundled ids lowercased), or an
    /// error for an id that names nothing or a custom theme that doesn't load (`ThemeResolver`).
    private func windowThemeID(in environment: CLIEnvironment) throws(CLIError) -> String? {
        guard let id = themeFlavor.theme else {
            return nil
        }
        do {
            return try ThemeResolver(themesFolder: environment.themesFolder).theme(id: id).id
        } catch {
            throw error.cliError
        }
    }

    /// A file the app can read: it exists, isn't a folder, and opens for reading. Failures are
    /// `ExitStatus.noInput` with the POSIX reason, as for `--html`.
    static func checkReadableFile(atPath path: String) throws(CLIError) {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw .posix(path, errno, status: ExitStatus.noInput)
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw .posix(path, errno, status: ExitStatus.noInput)
        }
        if info.st_mode & S_IFMT == S_IFDIR {
            throw .posix(path, EISDIR, status: ExitStatus.noInput)
        }
    }
}
