import Foundation

/// A per-test temp folder, deleted when the value goes away. Inputs and outputs live here, never
/// in the working directory.
final class TempFolder {
    let url: URL

    init() throws {
        // Realpath'd: /var is a link to /private/var, and paths in messages should match.
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        url = base.appending(path: "mdv-cli-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes `contents` to `name` and returns its path.
    @discardableResult
    func file(_ name: String, _ contents: String) throws -> String {
        try file(name, data: Data(contents.utf8))
    }

    @discardableResult
    func file(_ name: String, data: Data) throws -> String {
        let fileURL = url.appending(path: name)
        try data.write(to: fileURL)
        return fileURL.path
    }

    /// Copies the bundled fixture `name` (`Tests/MdvCLITests/Fixtures`) here.
    @discardableResult
    func fixture(_ name: String) throws -> String {
        guard let source = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
        }
        let destination = url.appending(path: name)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination.path
    }

    func path(_ name: String) -> String {
        url.appending(path: name).path
    }

    func contents(_ name: String) throws -> String {
        try String(contentsOf: url.appending(path: name), encoding: .utf8)
    }
}
