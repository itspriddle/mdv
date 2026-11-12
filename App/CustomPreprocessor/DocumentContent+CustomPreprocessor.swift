import Foundation
import PeepCore

extension DocumentContent {
    /// Renders `source`, the text of the file at `url` (nil for standard input, #68: titled
    /// "Standard Input" when it has no title of its own, with no allowed root, so relative
    /// images and page links resolve to nothing), with `preferences`: through the custom
    /// preprocessor first when `preferences.customPreprocessor` is set (#57), then the rest of
    /// the pipeline. The single render used by opening, reverting, live reload, and Settings
    /// changes (`MarkdownDocument.renderContent`). Runs off the main actor.
    ///
    /// A preprocessor failure (an executable that went away, a timeout, a crash, a non-zero
    /// exit, ...) is not an error here: the content is `source` rendered without it, with
    /// `preprocessorError` set for the window's bar. The only error is `CancellationError`,
    /// when the task is cancelled during the run (a newer render, or the document closed); the
    /// runner has then stopped the script's process group.
    ///
    /// The file was already decoded as UTF-8 (`source(from:)`), so the script gets exactly the
    /// file's bytes. Standard input's script runs with no document path, in `/`, as in the CLI.
    static func rendering(
        _ source: String, of url: URL?, preferences: MarkdownPreferences
    ) async throws -> DocumentContent {
        let fallbackTitle = url?.lastPathComponent ?? MarkdownDocument.standardInputName
        let linkRoot = linkRoot(forDocumentAt: url)
        guard let preference = preferences.customPreprocessor else {
            return DocumentContent(
                source: source, fallbackTitle: fallbackTitle, linkRoot: linkRoot, preferences: preferences,
                documentURL: url)
        }
        let renderedSource: String
        let preprocessorError: PreprocessorError?
        do {
            let configuration = try PreprocessorConfiguration(
                executablePath: preference.executablePath, arguments: preference.arguments)
            renderedSource = try await CustomPreprocessor(configuration: configuration)
                .run(input: Data(source.utf8), documentURL: url)
            preprocessorError = nil
        } catch let error as PreprocessorExecutableError {
            renderedSource = source
            preprocessorError = PreprocessorError(.executableUnavailable(error))
        } catch let error as PreprocessorError {
            renderedSource = source
            preprocessorError = error
        }
        try Task.checkCancellation()
        return DocumentContent(
            source: source, renderedSource: renderedSource, preprocessorError: preprocessorError,
            fallbackTitle: fallbackTitle, linkRoot: linkRoot, preferences: preferences, documentURL: url)
    }
}
