import ArgumentParser
import MdvCore

/// The custom preprocessor on request (#66). Headless output never runs one unless a flag asks.
public struct PreprocessorOptions: ParsableArguments, Sendable {
    public init() {}

    /// The Markdown to render for `document`: unchanged unless a preprocessor was asked for.
    /// A failure throws `CLIError` with the message and status #66 decides.
    func preprocess(_ document: InputDocument) async throws(CLIError) -> String {
        document.markdown
    }
}
