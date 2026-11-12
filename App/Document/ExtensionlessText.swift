import Foundation

/// Files with no extension (`README`, `CHANGELOG`, `LICENSE`) that Peep opens as plain text (#41).
///
/// Launch Services types such a file as `public.data`, which no document type of Peep's
/// declares, so the Open panel greys it out and a drop rejects it. Declaring `public.data` (or
/// raising the plain text rank) would make Peep a handler for every file, so instead the
/// `DocumentController` asks this type when the file's own type has no document class: an
/// extensionless regular file whose first bytes are UTF-8 text opens as plain text. Peep never
/// registers for these files; Finder's Open With and default-app choices are unchanged.
enum ExtensionlessText {
    /// How much of the file is read to decide. Enough to reject binaries quickly.
    static let sniffLength = 4096

    /// Whether `url` is an extensionless regular file whose start looks like UTF-8 text.
    nonisolated static func isPlainText(at url: URL) -> Bool {
        guard url.isFileURL, url.pathExtension.isEmpty else {
            return false
        }
        let path = url.path(percentEncoded: false)
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            return false
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }
        let data: Data
        do {
            // `nil` at end of file: an empty file.
            data = try handle.read(upToCount: sniffLength) ?? Data()
        } catch {
            return false
        }
        return looksLikeText(data, isTruncated: data.count == sniffLength)
    }

    /// Whether `data` is UTF-8 text without NUL bytes. An empty file counts as text. When
    /// `isTruncated`, up to three trailing bytes may be the start of a character cut off by the
    /// read.
    nonisolated static func looksLikeText(_ data: Data, isTruncated: Bool) -> Bool {
        guard !data.contains(0) else {
            return false
        }
        let cutOff = isTruncated ? min(3, data.count) : 0
        return (0...cutOff).contains { dropped in
            String(bytes: data.dropLast(dropped), encoding: .utf8) != nil
        }
    }
}
