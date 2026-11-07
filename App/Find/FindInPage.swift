import AppKit
import Observation

/// The page side of find in page: what `FindInPage` needs from the window's web view
/// (`WebViewCoordinator+Find.swift`, over `App/Scripts/FindInPage.js`). A protocol so the find
/// logic is tested without WebKit.
@MainActor
protocol FindInPageHost: AnyObject {
    /// Finds `query` and highlights every match, with none current yet.
    func findMatches(of query: String, caseSensitive: Bool, fromCurrent: Bool) async throws -> FindMatches
    /// Makes match `index` current (highlighted differently); scrolls it into view if `reveal`.
    func selectMatch(at index: Int, reveal: Bool) async throws
    /// Removes the highlights, optionally leaving the current match as the text selection.
    func clearMatches(selectingCurrent: Bool) async throws
    /// The page's selected text.
    func selectedText() async throws -> String
    /// Scrolls the current match, else the page's selected text, into view. Returns `false`
    /// when there is neither.
    func revealSelection() async throws -> Bool
    /// Gives the page keyboard focus (after the find bar closes).
    func focusPage()
}

/// The result of a search.
struct FindMatches: Equatable, Sendable {
    /// Matches found, up to the script's limit.
    var count: Int
    /// Whether counting stopped at the limit (there are more).
    var isLimited: Bool
    /// The match to start at: the first at or after the previous current match, or in view.
    var first: Int

    var isEmpty: Bool { count < 1 }
}

/// One window's find in page: the find bar's state and the operations behind Edit > Find.
///
/// Page operations run one at a time, in order, so a search always finishes before the step
/// that follows it. The query and options persist while the bar is closed and across reloads:
/// `refresh()` runs the search again on new content.
///
/// The query follows the shared find pasteboard (`pasteboard`): showing the bar or Find
/// Next/Previous adopts a search made elsewhere since this window last saw the pasteboard, and
/// each new query (typed, or Use Selection for Find) is written back to it.
@MainActor
@Observable
final class FindInPage {
    /// Whether the find bar is shown.
    private(set) var isVisible = false
    /// The search text.
    private(set) var query = ""
    /// Whether matching is case-sensitive (off by default).
    private(set) var isCaseSensitive = false
    /// Matches on the page for `query` (0 before a search).
    private(set) var matchCount = 0
    /// Whether there are more matches than `matchCount`.
    private(set) var isLimited = false
    /// The current match, 0-based.
    private(set) var currentIndex: Int?
    /// Whether the page has been searched for `query` with the current options.
    private(set) var hasSearched = false
    /// Changes each time the find field should take focus and select its text.
    private(set) var focusRequest = 0

    /// Longest query used (also capped in the script).
    static let maximumQueryLength = 1000

    @ObservationIgnored weak var host: (any FindInPageHost)?
    /// The shared find pasteboard; `nil` keeps the query to this window.
    @ObservationIgnored var pasteboard: (any FindPasteboard)? {
        didSet { sharedQuery = SharedFindQuery(pasteboard: pasteboard) }
    }
    @ObservationIgnored private var sharedQuery: SharedFindQuery
    @ObservationIgnored private var lastOperation: Task<Void, Never>?
    @ObservationIgnored private var pendingSearches = 0

    init(host: (any FindInPageHost)? = nil, pasteboard: (any FindPasteboard)? = nil) {
        self.host = host
        sharedQuery = SharedFindQuery(pasteboard: pasteboard)
        self.pasteboard = pasteboard
    }

    /// "3 of 12", "3 of 1000+", "Not found", or nil before there is anything to report.
    var status: String? {
        Self.statusText(
            query: query, hasSearched: hasSearched, count: matchCount, isLimited: isLimited, current: currentIndex)
    }

    /// Whether the last search found nothing.
    var isNotFound: Bool {
        hasSearched && matchCount == 0 && !Self.isBlank(query)
    }

    // MARK: Commands

    /// Edit > Find > Find… (Cmd-F): shows the bar, focuses its field, and searches for the
    /// existing query.
    func show() {
        focusRequest += 1
        let adopted = adoptPasteboardQuery()
        guard !isVisible else {
            if adopted {
                search(fromCurrent: false, reveal: true)
            }
            return
        }
        isVisible = true
        searchIfNeeded()
    }

    /// Esc or Done: hides the bar and the highlights, leaving the current match selected. The
    /// query is kept for the next search.
    func hide() {
        guard isVisible else {
            return
        }
        isVisible = false
        let selectingCurrent = currentIndex != nil
        resetResults()
        enqueue { host in
            try await host.clearMatches(selectingCurrent: selectingCurrent)
        }
        host?.focusPage()
    }

    /// Find Next (Cmd-G, Return in the field). Wraps from the last match to the first.
    func next() {
        step(forward: true)
    }

    /// Find Previous (Cmd-Shift-G, Shift-Return in the field). Wraps from the first to the last.
    func previous() {
        step(forward: false)
    }

    /// The find field's text changed: search incrementally, from the current match.
    func setQuery(_ newQuery: String) {
        let newQuery = String(newQuery.prefix(Self.maximumQueryLength))
        guard newQuery != query else {
            return
        }
        query = newQuery
        hasSearched = false
        publishQuery()
        if isVisible {
            search(fromCurrent: true, reveal: true)
        }
    }

    func setCaseSensitive(_ caseSensitive: Bool) {
        guard caseSensitive != isCaseSensitive else {
            return
        }
        isCaseSensitive = caseSensitive
        hasSearched = false
        if isVisible {
            search(fromCurrent: true, reveal: true)
        }
    }

    /// Use Selection for Find (Cmd-E): the page's selected text becomes the query.
    func useSelection() {
        enqueue { [weak self] host in
            let text = try await host.selectedText()
            self?.selectionDidLoad(text)
        }
    }

    /// Jump to Selection (Cmd-J): scrolls the current match (while the bar is open) or the
    /// page's selected text into view. Beeps when there is neither.
    func jumpToSelection() {
        enqueue { host in
            if try await !host.revealSelection() {
                NSSound.beep()
            }
        }
    }

    /// The page content changed (live reload, a full reload): find again on the new content,
    /// keeping the current match number where it still exists, without scrolling (the reading
    /// position is kept by the reload).
    func refresh() async {
        guard isVisible, !Self.isBlank(query) else {
            return
        }
        let keep = currentIndex
        resetResults()
        enqueue { [weak self] host in
            guard let self else {
                return
            }
            let matches = try await host.findMatches(of: query, caseSensitive: isCaseSensitive, fromCurrent: false)
            apply(matches)
            if !matches.isEmpty {
                let index = min(keep ?? matches.first, matches.count - 1)
                currentIndex = index
                try await host.selectMatch(at: index, reveal: false)
            }
        }
        await waitUntilIdle()
    }

    /// Waits for queued page operations (tests, and `refresh()`).
    func waitUntilIdle() async {
        await lastOperation?.value
    }

    // MARK: Logic

    /// The match after (or before) `index`, wrapping around; the first (or last) match when
    /// there is no current one, nil when there are none.
    nonisolated static func steppedIndex(from index: Int?, count: Int, forward: Bool) -> Int? {
        guard count > 0 else {
            return nil
        }
        guard let index, index >= 0, index < count else {
            return forward ? 0 : count - 1
        }
        return forward ? (index + 1) % count : (index + count - 1) % count
    }

    nonisolated static func statusText(
        query: String, hasSearched: Bool, count: Int, isLimited: Bool, current: Int?
    ) -> String? {
        guard hasSearched, !isBlank(query) else {
            return nil
        }
        guard count > 0 else {
            return "Not found"
        }
        let total = isLimited ? "\(count)+" : "\(count)"
        guard let current else {
            return count == 1 ? "1 match" : "\(total) matches"
        }
        return "\(current + 1) of \(total)"
    }

    nonisolated static func isBlank(_ query: String) -> Bool {
        query.allSatisfy(\.isWhitespace)
    }

    // MARK: Private

    private func step(forward: Bool) {
        let adopted = adoptPasteboardQuery()
        guard !Self.isBlank(query) else {
            show()
            return
        }
        isVisible = true
        if adopted || (!hasSearched && pendingSearches == 0) {
            search(fromCurrent: false, reveal: true)
            return
        }
        // After any search in flight, so Return right after typing goes to the next match.
        enqueue { [weak self] host in
            guard let self, hasSearched,
                let index = Self.steppedIndex(from: currentIndex, count: matchCount, forward: forward)
            else {
                return
            }
            currentIndex = index
            try await host.selectMatch(at: index, reveal: true)
        }
    }

    private func searchIfNeeded() {
        if !Self.isBlank(query) {
            search(fromCurrent: false, reveal: true)
        }
    }

    private func search(fromCurrent: Bool, reveal: Bool) {
        let query = query
        let caseSensitive = isCaseSensitive
        if Self.isBlank(query) {
            resetResults()
            enqueue { host in
                try await host.clearMatches(selectingCurrent: false)
            }
            return
        }
        pendingSearches += 1
        enqueue { [weak self] host in
            defer { self?.pendingSearches -= 1 }
            let matches = try await host.findMatches(of: query, caseSensitive: caseSensitive, fromCurrent: fromCurrent)
            // A newer query or option change supersedes this result; its own search follows.
            guard let self, self.query == query, isCaseSensitive == caseSensitive, isVisible else {
                return
            }
            apply(matches)
            if !matches.isEmpty {
                currentIndex = matches.first
                try await host.selectMatch(at: matches.first, reveal: reveal)
            }
        }
    }

    private func selectionDidLoad(_ text: String) {
        let text = SharedFindQuery.singleLine(text)
        guard !text.isEmpty else {
            return
        }
        if text == query {
            // Still a new search as far as other apps know.
            publishQuery()
        } else {
            setQuery(text)
        }
        focusRequest += isVisible ? 1 : 0
    }

    /// Takes a search made in another app or window since this one last looked (from the find
    /// pasteboard) as the query. Doesn't search; returns whether the query changed.
    private func adoptPasteboardQuery() -> Bool {
        guard let text = sharedQuery.newSearch(), text != query else {
            return false
        }
        query = text
        hasSearched = false
        return true
    }

    /// Shares a new query with other apps and windows.
    private func publishQuery() {
        sharedQuery.publish(query)
    }

    private func apply(_ matches: FindMatches) {
        matchCount = matches.count
        isLimited = matches.isLimited
        currentIndex = nil
        hasSearched = true
    }

    private func resetResults() {
        matchCount = 0
        isLimited = false
        currentIndex = nil
        hasSearched = false
    }

    /// Runs `operation` after every earlier one. A failure (no page loaded yet, the web content
    /// process exited) leaves the results reset; the next search or reload starts over.
    private func enqueue(_ operation: @escaping @MainActor (any FindInPageHost) async throws -> Void) {
        let previous = lastOperation
        lastOperation = Task { [weak self] in
            await previous?.value
            guard let host = self?.host else {
                return
            }
            do {
                try await operation(host)
            } catch {
                self?.resetResults()
            }
        }
    }
}
