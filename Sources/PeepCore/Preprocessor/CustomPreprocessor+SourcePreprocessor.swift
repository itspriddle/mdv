import Foundation

extension CustomPreprocessor {
    /// This preprocessor as the render pipeline's stage 1 (`SourcePreprocessor`) for one
    /// document: `MarkdownRenderer.render(_:preprocessor:)` with `for(documentURL:)`.
    public func `for`(documentURL: URL?) -> DocumentPreprocessor {
        DocumentPreprocessor(preprocessor: self, documentURL: documentURL)
    }
}

/// A `CustomPreprocessor` bound to the document it runs on (its path goes in
/// `PEEP_DOCUMENT_PATH` and its folder is the working directory). The source is sent as UTF-8;
/// `CustomPreprocessor.run(input:documentURL:)` takes raw bytes.
public struct DocumentPreprocessor: SourcePreprocessor {
    public let preprocessor: CustomPreprocessor
    public let documentURL: URL?

    public func preprocess(_ source: String) async throws -> String {
        try await preprocessor.run(input: Data(source.utf8), documentURL: documentURL)
    }
}
