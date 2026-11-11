import ArgumentParser
import Foundation
import MdvCore

/// The custom preprocessor on request (#66). Headless output never runs a program unless
/// `--preprocessor` names one; the app's Settings > Markdown preprocessor doesn't apply here.
///
/// The run is MdvCore's `CustomPreprocessor`, with the app's contract and limits: the input's
/// bytes on stdin, Markdown on stdout, `MDV_DOCUMENT_PATH` and the document's folder as the
/// working directory for a file (`/` and no path for standard input).
public struct PreprocessorOptions: ParsableArguments, Sendable {
    @Option(
        name: .customLong("preprocessor"),
        help: ArgumentHelp(
            "Run the program at PATH (a file, not a command name) on each input first: "
                + "the document on its stdin, Markdown on its stdout.",
            valueName: "PATH"))
    public var executable: String?

    @Option(
        name: .customLong("preprocessor-arg"),
        parsing: .unconditionalSingleValue,
        help: ArgumentHelp(
            "An argument for the --preprocessor program, passed as is (repeatable).", valueName: "ARG"))
    public var arguments: [String] = []

    public init() {}

    /// Whether a preprocessor flag was given. Like the Rendering flags they change HTML output
    /// only, so without `--html`, `--fragment`, or `--output` they are a usage error
    /// (`MdvCommand.validate()`).
    var isSet: Bool { executable != nil || !arguments.isEmpty }

    public func validate() throws {
        if executable == nil, !arguments.isEmpty {
            throw ValidationError("--preprocessor-arg needs --preprocessor.")
        }
        if executable?.isEmpty == true {
            throw ValidationError("--preprocessor needs the path of a program.")
        }
    }

    /// The Markdown to render for `document`: unchanged without `--preprocessor`, else the
    /// program's output. Any failure (the program can't run, exits non-zero, times out, writes
    /// too much or not UTF-8) is `ExitStatus.software`, with the reason and the tail of its
    /// stderr; nothing is rendered unprocessed.
    func preprocess(_ document: InputDocument, in environment: CLIEnvironment) async throws(CLIError) -> String {
        guard let executable else { return document.markdown }
        let subject = document.source.displayName
        let preprocessor: CustomPreprocessor
        do throws(PreprocessorExecutableError) {
            let configuration = try PreprocessorConfiguration(
                executablePath: Self.absolutePath(executable),
                arguments: arguments,
                limits: environment.preprocessorLimits)
            preprocessor = CustomPreprocessor(configuration: configuration)
        } catch {
            throw Self.failure(subject, PreprocessorError(.executableUnavailable(error)))
        }

        let input = Data(document.markdown.utf8)
        let documentURL = document.source.url
        let run: @Sendable () async throws -> String = {
            try await preprocessor.run(input: input, documentURL: documentURL)
        }
        do {
            return environment.cancelsOnInterrupt ? try await InterruptCancellation.run(run) : try await run()
        } catch let error as PreprocessorError {
            throw Self.failure(subject, error)
        } catch {
            // Cancelled. With live signal handling the signal has already ended the process.
            throw CLIError("\(subject): the preprocessor was interrupted", status: ExitStatus.interrupted)
        }
    }

    /// `path` made absolute against the working directory. It's a path, never a command name.
    static func absolutePath(_ path: String) -> String {
        URL(fileURLWithPath: path).absoluteURL.path(percentEncoded: false)
    }

    /// `mdv: <input>: <reason>`, then the program's stderr tail on the following lines, with
    /// control characters other than tabs and newlines escaped (it may echo the document).
    static func failure(_ subject: String, _ error: PreprocessorError) -> CLIError {
        var message = "\(subject): \(error.message)"
        let tail = error.standardError.trimmingCharacters(in: .newlines)
        if !tail.isEmpty {
            let lines = tail.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { line in
                line.split(separator: "\t", omittingEmptySubsequences: false)
                    .map { RenderFlagOptions.terminalSafe(String($0)) }
                    .joined(separator: "\t")
            }
            message += "\n" + lines.joined(separator: "\n")
        }
        return CLIError(message, status: ExitStatus.software)
    }
}
