import ArgumentParser
import Foundation

/// Headless output (#63): any of these flags renders HTML instead of opening the app.
///
/// - `--html`: a complete page per input, CSS inline and a strict CSP, no external resources
///   (so there's no separate `--standalone`).
/// - `--fragment`: the rendered body only, no `<html>`, `<head>`, or CSS, for embedding.
/// - `--output FILE`: written atomically, never over an input.
///
/// Several inputs print back to back only as fragments: concatenated pages aren't a valid HTML
/// document, and `--output` takes one input (`MdvCommand.validate()`).
public struct OutputOptions: ParsableArguments, Sendable {
    @Flag(name: .long, help: "Print a complete HTML page (CSS inline) instead of opening the app.")
    public var html = false

    @Flag(
        name: .long,
        help: "Print only the rendered body HTML (no <html>, <head>, or CSS), for embedding. Implies --html.")
    public var fragment = false

    @Option(
        name: [.short, .long],
        help: ArgumentHelp(
            "Write to FILE instead of standard output, replacing it atomically; never an input file. Implies --html.",
            valueName: "FILE"),
        completion: .file())
    public var output: String?

    public init() {}

    /// Whether this run renders HTML rather than opening the app.
    public var rendersHTML: Bool { html || fragment || output != nil }

    public var destination: OutputDestination {
        guard let output, output != "-" else { return .standardOutput }
        return .file(output)
    }

    public func validate() throws {
        if output?.isEmpty == true {
            throw ValidationError("--output needs a file name.")
        }
    }
}

/// Where headless output goes. `-o -` is standard output.
public enum OutputDestination: Equatable, Sendable {
    case standardOutput
    case file(String)

    /// Writes `text`. A file is checked against `inputs` first (exit 64 if it is one of them,
    /// symbolic and hard links included), then replaced atomically: a temp file in the same folder
    /// renamed over it, so a failed write leaves the old file as it was.
    func write(_ text: String, inputs: [InputSource], in environment: CLIEnvironment) throws(CLIError) {
        let data = Data(text.utf8)
        switch self {
        case .standardOutput:
            do {
                try environment.standardOutput.write(data)
            } catch {
                throw CLIError("stdout: \(error.localizedDescription)", status: ExitStatus.ioError)
            }
        case .file(let path):
            if let identity = FileIdentity(path: path),
                inputs.contains(where: { input in input.url.flatMap { FileIdentity(path: $0.path) } == identity })
            {
                throw .usage("\(path): refusing to overwrite an input file")
            }
            do {
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            } catch {
                throw CLIError("\(path): \(Self.reason(error))", status: ExitStatus.cannotCreate)
            }
        }
    }

    /// The POSIX message when Foundation has one (`Permission denied`), else its description.
    private static func reason(_ error: any Error) -> String {
        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
            underlying.domain == NSPOSIXErrorDomain
        {
            return String(cString: strerror(Int32(underlying.code)))
        }
        return nsError.localizedDescription
    }
}

/// A file's device and inode, following symbolic links: two paths to the same file match.
struct FileIdentity: Equatable {
    let device: dev_t
    let inode: ino_t

    init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        device = info.st_dev
        inode = info.st_ino
    }
}
