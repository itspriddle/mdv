/// Decides which outline entry is selected: the current section as the reader scrolls, without
/// taking the selection away from someone using the outline.
///
/// - Scrolling the document selects the section at the reading position (`scrolled(to:)`).
/// - Moving the selection in the outline with the keyboard (`browsed(to:)`) is browsing: scroll
///   reports don't move the selection until the reader jumps (`jumped(to:)`) or leaves the
///   outline (`stoppedBrowsing()`).
/// - After a jump the target stays selected until the document is scrolled away from where the
///   jump landed (`landed(at:)`). A heading near the end of a page can't reach the top of the
///   view, so the section at the reading position may be an earlier one; the reader still sees
///   the heading they chose.
///
/// Positions are fractional source lines, as `DocumentOutline.section(atSourceLine:)` takes.
public struct OutlineTracker: Sendable {
    /// The outline being tracked.
    public private(set) var outline: DocumentOutline
    /// The section at the last reported reading position.
    public private(set) var currentSection: String?
    /// The entry the outline should show selected.
    public private(set) var selection: String?

    /// How far (in source lines) the position may move after a jump and still count as where
    /// the jump landed.
    public static let landingTolerance = 0.01

    private var isBrowsing = false
    private var jump: (id: String, line: Double?)?
    private var lastLine: Double?

    public init(outline: DocumentOutline = DocumentOutline(headings: [])) {
        self.outline = outline
    }

    /// The document scrolled; `line` is the new reading position.
    public mutating func scrolled(to line: Double) {
        lastLine = line
        currentSection = outline.section(atSourceLine: line)
        if let jump, let landing = jump.line, abs(line - landing) > Self.landingTolerance {
            self.jump = nil
        }
        updateSelection()
    }

    /// The reader moved the outline's selection without jumping (arrow keys).
    public mutating func browsed(to id: String?) {
        isBrowsing = true
        selection = id
    }

    /// The reader left the outline (it lost keyboard focus); the selection follows scrolling
    /// again.
    public mutating func stoppedBrowsing() {
        isBrowsing = false
        updateSelection()
    }

    /// The reader chose `id` (click or Return); the document is scrolling to it.
    public mutating func jumped(to id: String) {
        isBrowsing = false
        jump = (id, nil)
        selection = id
    }

    /// The jump finished with the reading position at `line`.
    public mutating func landed(at line: Double) {
        guard let jump, jump.line == nil else {
            return
        }
        self.jump = (jump.id, line)
        lastLine = line
        currentSection = outline.section(atSourceLine: line)
    }

    /// The document was re-rendered. Selections and jumps whose heading is gone are dropped;
    /// the current section is recomputed when the next position arrives (`scrolled(to:)`),
    /// since source lines may have moved.
    public mutating func update(_ outline: DocumentOutline) {
        self.outline = outline
        if let jump, !outline.contains(jump.id) {
            self.jump = nil
        }
        if isBrowsing, let selection, !outline.contains(selection) {
            isBrowsing = false
        }
        if let lastLine {
            currentSection = outline.section(atSourceLine: lastLine)
        }
        updateSelection()
    }

    private mutating func updateSelection() {
        guard !isBrowsing else {
            return
        }
        selection = jump?.id ?? currentSection
    }
}
