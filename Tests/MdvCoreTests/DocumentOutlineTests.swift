import Testing

@testable import MdvCore

private func outline(_ source: String) -> DocumentOutline {
    var options = RenderOptions()
    options.sourceLines = true
    return DocumentOutline(headings: HTMLRenderer(options: options).render(source).headings)
}

/// `(slug, children)` pairs, for comparing trees.
private indirect enum Shape: Equatable {
    case node(String, [Shape])
}

private func shape(_ entries: [DocumentOutline.Entry]) -> [Shape] {
    entries.map { .node($0.id, shape($0.children)) }
}

@Suite("DocumentOutline")
struct DocumentOutlineTests {
    @Test("nests headings under the nearest earlier lower-level heading")
    func nesting() {
        let tree = outline(
            """
            # Title
            ## Install
            ### macOS
            ### Linux
            ## Usage
            # Appendix
            """)
        #expect(
            shape(tree.roots) == [
                .node("title", [.node("install", [.node("macos", []), .node("linux", [])]), .node("usage", [])]),
                .node("appendix", []),
            ])
    }

    @Test("skipped levels nest one step; leading deeper headings are roots")
    func skippedLevels() {
        let tree = outline("### Early\n\n# Top\n\n### Deep\n\n## Middle\n")
        #expect(shape(tree.roots) == [.node("early", []), .node("top", [.node("deep", []), .node("middle", [])])])
    }

    @Test("duplicate headings are separate entries with unique ids")
    func duplicates() {
        let tree = outline("# Notes\n\n## Example\n\n## Example\n\n# Notes\n")
        #expect(
            shape(tree.roots) == [
                .node("notes", [.node("example", []), .node("example-1", [])]), .node("notes-1", []),
            ])
        #expect(tree.headings.map(\.text) == ["Notes", "Example", "Example", "Notes"])
    }

    @Test("raw HTML headings are included")
    func rawHTML() {
        let tree = outline("# Top\n\n<h2>Raw <em>one</em></h2>\n\n## After\n")
        #expect(shape(tree.roots) == [.node("top", [.node("raw-one", []), .node("after", [])])])
    }

    @Test("an empty document has an empty outline")
    func empty() {
        let tree = outline("Just text.\n")
        #expect(tree.isEmpty)
        #expect(tree.roots.isEmpty)
        #expect(tree.section(atSourceLine: 1) == nil)
    }

    @Test(
        "the section at a source line is the last heading at or before it",
        arguments: [
            (1.0, nil),
            (2.9, nil),
            (3.0, "one"),
            (4.5, "one"),
            (7.0, "two"),
            (100.0, "three"),
        ] as [(Double, String?)])
    func section(line: Double, expected: String?) {
        // Lines: 1 text, 3 # One, 5 text, 7 ## Two, 9 text, 11 # Three
        let tree = outline("Intro.\n\n# One\n\ntext\n\n## Two\n\ntext\n\n# Three\n")
        #expect(tree.section(atSourceLine: line) == expected)
    }

    @Test("ancestors of an entry, outermost first")
    func ancestors() {
        let tree = outline("# A\n## B\n### C\n# D\n")
        #expect(tree.ancestors(of: "c") == ["a", "b"])
        #expect(tree.ancestors(of: "d").isEmpty)
        #expect(tree.ancestors(of: "missing").isEmpty)
        #expect(tree.contains("b"))
        #expect(!tree.contains("missing"))
    }
}

@Suite("OutlineTracker")
struct OutlineTrackerTests {
    // Lines: 1 # One, 3 text, 5 # Two, 7 text, 9 # Three
    let outline = DocumentOutlineTests.sample

    @Test("scrolling selects the current section")
    func scrolling() {
        var tracker = OutlineTracker(outline: outline)
        #expect(tracker.selection == nil)
        tracker.scrolled(to: 1)
        #expect(tracker.selection == "one")
        tracker.scrolled(to: 6)
        #expect(tracker.selection == "two")
        #expect(tracker.currentSection == "two")
    }

    @Test("browsing with the keyboard keeps the selection while the document scrolls")
    func browsing() {
        var tracker = OutlineTracker(outline: outline)
        tracker.scrolled(to: 1)
        tracker.browsed(to: "three")
        tracker.scrolled(to: 5)
        #expect(tracker.selection == "three")
        #expect(tracker.currentSection == "two")
        tracker.stoppedBrowsing()
        #expect(tracker.selection == "two")
    }

    @Test("a jump keeps its target selected until the reader scrolls away from the landing")
    func jumpPinsUntilScrolled() {
        var tracker = OutlineTracker(outline: outline)
        tracker.scrolled(to: 1)
        tracker.jumped(to: "three")
        #expect(tracker.selection == "three")
        // A short last section can't reach the top: the view lands in section two.
        tracker.landed(at: 6)
        #expect(tracker.selection == "three")
        tracker.scrolled(to: 6)
        #expect(tracker.selection == "three", "the debounced report of the jump itself")
        tracker.scrolled(to: 4)
        #expect(tracker.selection == "one")
    }

    @Test("a scroll report before the landing keeps the jump target")
    func reportBeforeLanding() {
        var tracker = OutlineTracker(outline: outline)
        tracker.jumped(to: "two")
        tracker.scrolled(to: 3)
        #expect(tracker.selection == "two")
        tracker.landed(at: 5)
        tracker.scrolled(to: 5)
        #expect(tracker.selection == "two")
    }

    @Test("a jump ends browsing")
    func jumpEndsBrowsing() {
        var tracker = OutlineTracker(outline: outline)
        tracker.browsed(to: "two")
        tracker.jumped(to: "two")
        tracker.landed(at: 5)
        tracker.scrolled(to: 9)
        #expect(tracker.selection == "three")
    }

    @Test("a re-render keeps the selection when its heading remains and drops it when gone")
    func update() {
        var tracker = OutlineTracker(outline: outline)
        tracker.scrolled(to: 6)
        #expect(tracker.selection == "two")
        // Two lines inserted at the top: the same position now reads as section one.
        let shifted = DocumentOutline(
            headings: outline.headings.map {
                var heading = $0
                heading.sourceLine = (heading.sourceLine ?? 0) + 2
                return heading
            })
        tracker.update(shifted)
        #expect(tracker.selection == "one")
        tracker.browsed(to: "three")
        tracker.update(DocumentOutline(headings: Array(outline.headings.prefix(2))))
        #expect(tracker.selection == "two", "browsing ends when the browsed heading is removed")
    }
}

extension DocumentOutlineTests {
    static let sample = DocumentOutline(headings: [
        Heading(level: 1, text: "One", slug: "one", sourceLine: 1),
        Heading(level: 1, text: "Two", slug: "two", sourceLine: 5),
        Heading(level: 1, text: "Three", slug: "three", sourceLine: 9),
    ])
}
