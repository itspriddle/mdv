import Darwin
import Foundation

/// A configured custom preprocessor (#56): an executable and its fixed arguments.
///
/// The executable is an absolute path, standardized (`.` and `..` removed) and stored as
/// given: it is never looked up on `PATH`, and symbolic links are followed only to check the
/// target, so a Homebrew upgrade that moves the link's target keeps working. It is checked
/// here and again before every run (`validateExecutable()`); the file must exist, be a
/// regular file (after links), and be executable by this user. Arguments are passed as an
/// argv array, verbatim: no shell, no expansion, and nothing from the document is ever added.
public struct PreprocessorConfiguration: Sendable, Equatable {
    /// The standardized absolute path of the executable.
    public let executablePath: String
    /// Passed after `argv[0]` exactly as given.
    public let arguments: [String]
    public let limits: PreprocessorLimits

    /// Validates the executable and arguments; throws the first problem found.
    public init(
        executablePath: String,
        arguments: [String] = [],
        limits: PreprocessorLimits = .standard
    ) throws(PreprocessorExecutableError) {
        guard executablePath.hasPrefix("/") else { throw .notAbsolute(executablePath) }
        guard !executablePath.utf8.contains(0) else { throw .invalidPath }
        for argument in arguments where argument.utf8.contains(0) {
            throw .invalidArgument(argument)
        }
        self.executablePath = URL(filePath: executablePath).standardizedFileURL.path(percentEncoded: false)
        self.arguments = arguments
        self.limits = limits
        try validateExecutable()
    }

    /// Checks that the executable still exists, is a regular file, and is executable.
    public func validateExecutable() throws(PreprocessorExecutableError) {
        var info = stat()
        guard stat(executablePath, &info) == 0 else {
            if errno == ENOENT || errno == ENOTDIR { throw .notFound(executablePath) }
            throw .unreadable(executablePath, errno: errno)
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw .notRegularFile(executablePath) }
        guard access(executablePath, X_OK) == 0 else { throw .notExecutable(executablePath) }
    }
}

/// Why a configured executable can't be used. `description` is user-presentable.
public enum PreprocessorExecutableError: Error, Sendable, Equatable, CustomStringConvertible {
    case notAbsolute(String)
    case invalidPath
    case invalidArgument(String)
    case notFound(String)
    case unreadable(String, errno: Int32)
    case notRegularFile(String)
    case notExecutable(String)

    public var description: String {
        switch self {
        case .notAbsolute(let path): "“\(path)” is not an absolute path."
        case .invalidPath: "The executable path contains a NUL character."
        case .invalidArgument(let argument): "The argument “\(argument)” contains a NUL character."
        case .notFound(let path): "“\(path)” doesn’t exist."
        case .unreadable(let path, let code): "“\(path)” can’t be checked: \(String(cString: strerror(code)))."
        case .notRegularFile(let path): "“\(path)” is not a file."
        case .notExecutable(let path): "“\(path)” is not executable."
        }
    }
}
