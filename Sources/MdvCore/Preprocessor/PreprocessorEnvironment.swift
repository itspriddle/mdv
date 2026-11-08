import Foundation

/// What a custom preprocessor's process starts with (#56): a minimal, explicit environment
/// (never the app's own) and a working directory.
///
/// - `PATH`: `defaultPath`, the system folders plus Homebrew's (fixed, so a script behaves
///   the same whether mdv was opened from Finder or a terminal).
/// - `HOME`, `TMPDIR`: this user's.
/// - `LANG`: `en_US.UTF-8`, since the contract is UTF-8 both ways.
/// - `MDV_DOCUMENT_PATH`: the document's absolute path, when there is a file. The path is
///   never an argument, where it could be taken for an option.
///
/// The working directory is the document's folder, so relative paths in the document (and in
/// the script's own includes) mean what they mean to the reader; with no document file
/// (piped input) it is `/`.
struct PreprocessorEnvironment: Equatable {
    static let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    static let documentPathVariable = "MDV_DOCUMENT_PATH"

    /// `NAME=value` entries, sorted by name.
    let variables: [String]
    let workingDirectory: String

    init(documentURL: URL?) {
        var values = [
            "PATH": Self.defaultPath,
            "HOME": NSHomeDirectory(),
            "TMPDIR": NSTemporaryDirectory(),
            "LANG": "en_US.UTF-8",
        ]
        if let documentURL, documentURL.isFileURL {
            let path = documentURL.standardizedFileURL.path(percentEncoded: false)
            values[Self.documentPathVariable] = path
            workingDirectory = documentURL.standardizedFileURL.deletingLastPathComponent().path(percentEncoded: false)
        } else {
            workingDirectory = "/"
        }
        variables = values.filter { !$0.value.utf8.contains(0) }.sorted { $0.key < $1.key }.map {
            "\($0.key)=\($0.value)"
        }
    }
}
