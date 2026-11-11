import ArgumentParser
import Foundation

/// The documents to read: FILE arguments, `-` for standard input, or standard input alone when
/// there are none (#68 owns how standard input reaches the app).
public struct InputOptions: ParsableArguments, Sendable {
    @Argument(help: ArgumentHelp("Markdown files. '-' or no FILE reads standard input.", valueName: "FILE"))
    public var files: [String] = []

    public init() {}

    /// The inputs in argument order; standard input alone when no FILE was given.
    public var sources: [InputSource] {
        files.isEmpty ? [.standardInput] : files.map { $0 == "-" ? .standardInput : .file($0) }
    }

    /// Standard input is read when no FILE is given and it isn't a terminal, or when `-` asks.
    var readsStandardInputImplicitly: Bool { files.isEmpty }

    public func validate() throws {
        if files.filter({ $0 == "-" }).count > 1 {
            throw ValidationError("'-' (standard input) can only be given once.")
        }
    }
}

/// One input: a file path as the reader typed it, or standard input.
public enum InputSource: Equatable, Sendable {
    case file(String)
    case standardInput

    /// The file's absolute URL (relative paths resolve against the working directory).
    public var url: URL? {
        guard case .file(let path) = self else { return nil }
        return URL(fileURLWithPath: path).absoluteURL
    }

    /// How errors name this input: the path as given, or `stdin`.
    public var displayName: String {
        switch self {
        case .file(let path): path
        case .standardInput: "stdin"
        }
    }

    /// The page title when the document has none: the file name, or `stdin`.
    public var fallbackTitle: String {
        url?.lastPathComponent ?? "stdin"
    }
}

/// An input's decoded Markdown.
public struct InputDocument: Equatable, Sendable {
    public var source: InputSource
    public var markdown: String

    public init(source: InputSource, markdown: String) {
        self.source = source
        self.markdown = markdown
    }

    /// Reads and decodes `source`. A missing, unreadable, or directory input is
    /// `ExitStatus.noInput`; bytes that aren't UTF-8 are `ExitStatus.dataError`.
    static func read(_ source: InputSource, in environment: CLIEnvironment) throws(CLIError) -> InputDocument {
        let data: Data
        switch source {
        case .file(let path):
            data = try readFile(atPath: path)
        case .standardInput:
            do {
                data = try environment.readStandardInput()
            } catch {
                throw CLIError("stdin: \(error.localizedDescription)", status: ExitStatus.noInput)
            }
        }
        guard let markdown = String(bytes: data, encoding: .utf8) else {
            throw CLIError("\(source.displayName): not valid UTF-8", status: ExitStatus.dataError)
        }
        return InputDocument(source: source, markdown: markdown)
    }

    /// POSIX reads, so the error is the `errno` message (`No such file or directory`, `Is a
    /// directory`, `Permission denied`). Pipes such as `<(cmd)` work.
    private static func readFile(atPath path: String) throws(CLIError) -> Data {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw .posix(path, errno, status: ExitStatus.noInput)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw .posix(path, errno, status: ExitStatus.noInput)
        }
        if info.st_mode & S_IFMT == S_IFDIR {
            throw .posix(path, EISDIR, status: ExitStatus.noInput)
        }
        do {
            return try handle.readToEnd() ?? Data()
        } catch {
            throw CLIError("\(path): \(error.localizedDescription)", status: ExitStatus.noInput)
        }
    }
}
