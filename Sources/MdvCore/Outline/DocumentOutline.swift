/// A document's headings as a tree, for the viewer's outline sidebar.
///
/// Each heading is a child of the nearest earlier heading with a lower level, so skipped levels
/// (an `h1` followed by an `h3`) nest one step, not two. Headings before any lower-level heading
/// are roots. Entries are identified by `slug`, which the renderer makes unique within a
/// document (duplicate headings get `-1`, `-2`, ...), so identity survives a re-render as long
/// as the heading's text does.
public struct DocumentOutline: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Identifiable {
        /// The heading's slug (its anchor id).
        public var id: String { heading.slug }
        public var heading: Heading
        public var children: [Entry]

        public init(heading: Heading, children: [Entry] = []) {
            self.heading = heading
            self.children = children
        }
    }

    /// Top-level entries, in document order.
    public let roots: [Entry]
    /// Every heading, in document order.
    public let headings: [Heading]

    public init(headings: [Heading]) {
        self.headings = headings
        self.roots = Self.tree(headings[...])
    }

    public var isEmpty: Bool { headings.isEmpty }

    /// Builds sibling entries from `headings`: each one takes the following headings with a
    /// higher level as its children.
    private static func tree(_ headings: ArraySlice<Heading>) -> [Entry] {
        var entries: [Entry] = []
        var index = headings.startIndex
        while index < headings.endIndex {
            let heading = headings[index]
            var end = headings.index(after: index)
            while end < headings.endIndex, headings[end].level > heading.level {
                end = headings.index(after: end)
            }
            entries.append(Entry(heading: heading, children: tree(headings[headings.index(after: index)..<end])))
            index = end
        }
        return entries
    }

    /// The slug of the section a reader is in when `line` (a fractional source line, as the
    /// app's scroll bridge reports it) is at the top of the view: the last heading at or before
    /// `line`. `nil` before the first heading. Headings without a source line are skipped.
    public func section(atSourceLine line: Double) -> String? {
        var current: String?
        for heading in headings {
            guard let sourceLine = heading.sourceLine else {
                continue
            }
            if Double(sourceLine) > line {
                break
            }
            current = heading.slug
        }
        return current
    }

    /// The slugs of `id`'s ancestors, outermost first; empty for a root or an unknown slug.
    public func ancestors(of id: String) -> [String] {
        func search(_ entries: [Entry], path: [String]) -> [String]? {
            for entry in entries {
                if entry.id == id {
                    return path
                }
                if let found = search(entry.children, path: path + [entry.id]) {
                    return found
                }
            }
            return nil
        }
        return search(roots, path: []) ?? []
    }

    /// Whether some heading has slug `id`.
    public func contains(_ id: String) -> Bool {
        headings.contains { $0.slug == id }
    }
}
