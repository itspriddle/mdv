import AppKit

/// The shared find pasteboard (`NSPasteboard.Name.find`), or a stand-in for tests: the search
/// text every Mac app reads when its find opens and writes when a search changes, so a search
/// started in one app (or window) carries over to the next.
@MainActor
protocol FindPasteboard: AnyObject {
    /// Changes whenever any app writes the pasteboard.
    var changeCount: Int { get }
    /// The search text on the pasteboard, if any.
    func findString() -> String?
    /// Replaces the pasteboard's contents with `string`. Returns the new `changeCount`.
    func writeFindString(_ string: String) -> Int
}

extension NSPasteboard: FindPasteboard {
    func findString() -> String? {
        string(forType: .string)
    }

    func writeFindString(_ string: String) -> Int {
        clearContents()
        setString(string, forType: .string)
        return changeCount
    }
}

/// One window's view of the find pasteboard: which searches are new to it, and sharing its own.
@MainActor
struct SharedFindQuery {
    let pasteboard: (any FindPasteboard)?
    /// The pasteboard's `changeCount` when this window last read or wrote it.
    private var seenChangeCount: Int?

    init(pasteboard: (any FindPasteboard)?) {
        self.pasteboard = pasteboard
    }

    /// The pasteboard's search text, as one line and at most `FindInPage.maximumQueryLength`
    /// long, if another app or window wrote it since this window last read or wrote it; else
    /// nil. A blank search is ignored.
    mutating func newSearch() -> String? {
        guard let pasteboard, pasteboard.changeCount != seenChangeCount else {
            return nil
        }
        seenChangeCount = pasteboard.changeCount
        guard let string = pasteboard.findString() else {
            return nil
        }
        let text = String(Self.singleLine(string).prefix(FindInPage.maximumQueryLength))
        return FindInPage.isBlank(text) ? nil : text
    }

    /// Writes `query` to the pasteboard, unless it is blank.
    mutating func publish(_ query: String) {
        guard let pasteboard, !FindInPage.isBlank(query) else {
            return
        }
        seenChangeCount = pasteboard.writeFindString(query)
    }

    /// `text` as one line: newlines and runs of whitespace match any whitespace anyway.
    nonisolated static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
