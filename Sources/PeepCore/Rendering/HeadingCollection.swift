/// A tree's headings in document order with unique slugs: Markdown headings and, in sanitized
/// trees, raw HTML `<h1>`–`<h6>` (#19), which github.com anchors the same way.
///
/// One `HeadingSlugger` covers both kinds, in the order the headings start, so a raw heading and
/// a Markdown heading with the same text get `slug` and `slug-1` as on GitHub.
///
/// A raw heading's slug source is its DOM `textContent`: the text of the raw HTML up to its end
/// tag, plus any Markdown nodes in between (cmark splits `<h2>`, a paragraph, and `</h2>` into
/// sibling nodes). Character references in raw text are decoded where `AttributeValue` decodes
/// them (numeric and ASCII-valued named ones); other named references (`&copy;`) stay as
/// written, a known difference from GitHub for headings that use them.
struct HeadingCollection {
    /// Every heading in document order.
    private(set) var headings: [Heading] = []
    /// The slugs of the tree's `.heading` nodes, in pre-order (the renderer's walk order).
    private(set) var markdownSlugs: [String] = []
    /// One anchor per raw HTML heading start tag, in pre-order of the raw-HTML nodes.
    private(set) var rawAnchors: [RawHeadingAnchor] = []

    private struct Entry {
        var level: Int
        var display = ""
        var slugSource = ""
        var sourceLine: Int?
        var isRaw: Bool
        var hasID = false
    }

    private var entries: [Entry] = []
    /// Indices in `entries` of the raw headings whose end tag hasn't been seen, innermost last.
    private var openRaw: [Int] = []

    /// Collects the headings under `root`. Pass `includingRawHTML` only for a sanitized tree:
    /// the raw HTML must be `HTMLSanitizer` output (balanced, re-serialized tags).
    init(_ root: MarkdownNode, includingRawHTML: Bool) {
        var stack = [root]
        while let node = stack.popLast() {
            switch node.kind {
            case .heading(let level):
                let text = HeadingText(node)
                entries.append(
                    Entry(
                        level: level, display: text.display.trimmingCharacters(in: .whitespacesAndNewlines),
                        slugSource: text.slugSource, sourceLine: node.sourceRange?.start.line, isRaw: false))
            case .htmlBlock(let html), .htmlInline(let html):
                if includingRawHTML {
                    scanRawHTML(html, sourceLine: node.sourceRange?.start.line)
                }
                continue
            case .image:
                // Alt text is not part of `textContent`.
                continue
            case .text(let text), .code(let text):
                appendToOpenRaw(slug: text, display: text)
            case .emoji(let shortcode, let character):
                appendToOpenRaw(slug: ":\(shortcode):", display: character)
            case .softBreak, .lineBreak:
                appendToOpenRaw(slug: "\n", display: " ")
            case .footnoteReference(_, let number, _):
                appendToOpenRaw(slug: String(number), display: "")
            case .codeBlock(let block):
                appendToOpenRaw(slug: block.literal, display: block.literal)
            default:
                break
            }
            stack.append(contentsOf: node.children.reversed())
        }

        var slugger = HeadingSlugger()
        for entry in entries {
            let slug = slugger.uniqueSlug(for: entry.slugSource)
            let text = entry.isRaw ? Self.collapsingWhitespace(entry.display) : entry.display
            headings.append(Heading(level: entry.level, text: text, slug: slug, sourceLine: entry.sourceLine))
            if entry.isRaw {
                rawAnchors.append(RawHeadingAnchor(slug: slug, hasID: entry.hasID))
            } else {
                markdownSlugs.append(slug)
            }
        }
        entries.removeAll()
    }

    private mutating func scanRawHTML(_ html: String, sourceLine: Int?) {
        // Nothing to collect: no heading open and no heading start tag in this node.
        guard !openRaw.isEmpty || html.contains("<h") else {
            return
        }
        var tokenizer = HTMLTokenizer(html)
        while let token = tokenizer.next() {
            switch token {
            case .text(let text):
                let decoded = AttributeValue(text).decoded
                appendToOpenRaw(slug: decoded, display: decoded)
            case .startTag(let tag):
                guard let level = RawHeadingAnchor.level(ofTag: tag.name) else {
                    continue
                }
                openRaw.append(entries.count)
                entries.append(
                    Entry(
                        level: level, sourceLine: sourceLine, isRaw: true,
                        hasID: tag.attributes.contains { $0.name == "id" }))
            case .endTag(let name):
                guard let level = RawHeadingAnchor.level(ofTag: name),
                    let index = openRaw.lastIndex(where: { entries[$0].level == level })
                else {
                    continue
                }
                openRaw.removeSubrange(index...)
            case .comment:
                continue
            }
        }
    }

    private mutating func appendToOpenRaw(slug: String, display: String) {
        for index in openRaw {
            entries[index].slugSource += slug
            entries[index].display += display
        }
    }

    private static func collapsingWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Returns `root` with an `id` and anchor link added to every raw HTML heading, using
    /// `rawAnchors` in order. The markup matches Markdown headings: `<hN … id="slug"><a
    /// class="anchor" aria-hidden="true" href="#slug"></a>`. A heading that already has an `id`
    /// (prefixed `user-content-` by the sanitizer) keeps it, and the slug goes on the anchor link.
    func anchoringRawHeadings(in root: MarkdownNode) -> MarkdownNode {
        guard !rawAnchors.isEmpty else {
            return root
        }
        var anchors = rawAnchors.makeIterator()
        return Self.mapRawHTML(in: root) { html in
            guard html.contains("<h") else {
                return html
            }
            return Self.anchoring(html, with: &anchors)
        }
    }

    /// Inserts anchors into the heading start tags of one sanitized raw-HTML string.
    private static func anchoring(_ html: String, with anchors: inout IndexingIterator<[RawHeadingAnchor]>) -> String {
        let scalars = Array(html.unicodeScalars)
        var output = String.UnicodeScalarView()
        var copied = 0
        var tokenizer = HTMLTokenizer(html)
        while let token = tokenizer.next() {
            guard case .startTag(let tag) = token, RawHeadingAnchor.level(ofTag: tag.name) != nil,
                let anchor = anchors.next()
            else {
                continue
            }
            // Sanitized heading start tags are never self-closing: the tag ends with `>`.
            let tagEnd = tokenizer.scalarOffset - 1
            guard tagEnd >= copied, scalars[tagEnd] == ">" else {
                continue
            }
            output.append(contentsOf: scalars[copied..<tagEnd])
            let slug = escapedAttribute(anchor.slug)
            let headingID = anchor.hasID ? "" : " id=\"\(slug)\""
            let linkID = anchor.hasID ? " id=\"\(slug)\"" : ""
            let markup = "\(headingID)><a\(linkID) class=\"anchor\" aria-hidden=\"true\" href=\"#\(slug)\"></a>"
            output.append(contentsOf: markup.unicodeScalars)
            copied = tagEnd + 1
        }
        output.append(contentsOf: scalars[copied...])
        return String(output)
    }

    /// Slugs hold only word characters and `-`; escaped anyway, since they become markup.
    private static func escapedAttribute(_ value: String) -> String {
        var escaped = ""
        for character in value {
            switch character {
            case "&": escaped += "&amp;"
            case "\"": escaped += "&quot;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    /// Rebuilds `root`, passing the string of each raw-HTML node to `transform` in pre-order
    /// (skipping image alt text, like the collection). Uses an explicit stack, no recursion.
    private static func mapRawHTML(in root: MarkdownNode, _ transform: (String) -> String) -> MarkdownNode {
        struct Frame {
            var node: MarkdownNode
            var nextChild = 0
            var children: [MarkdownNode] = []
        }
        var stack = [Frame(node: root)]
        while let top = stack.indices.last {
            guard stack[top].nextChild < stack[top].node.children.count else {
                let frame = stack.removeLast()
                var node = frame.node
                node.children = frame.children
                guard !stack.isEmpty else {
                    return node
                }
                stack[stack.count - 1].children.append(node)
                continue
            }
            var child = stack[top].node.children[stack[top].nextChild]
            stack[top].nextChild += 1
            switch child.kind {
            case .htmlBlock(let html):
                child.kind = .htmlBlock(transform(html))
                stack[top].children.append(child)
            case .htmlInline(let html):
                child.kind = .htmlInline(transform(html))
                stack[top].children.append(child)
            case .image:
                stack[top].children.append(child)
            default:
                if child.children.isEmpty {
                    stack[top].children.append(child)
                } else {
                    stack.append(Frame(node: child))
                }
            }
        }
        return root
    }
}

/// The anchor a raw HTML heading gets.
struct RawHeadingAnchor: Equatable {
    var slug: String
    /// The heading already has an `id`, so the slug goes on its anchor link instead.
    var hasID: Bool

    /// 1...6 for `h1`...`h6` (sanitized tag names are lowercase), else `nil`.
    static func level(ofTag name: String) -> Int? {
        guard name.count == 2, name.hasPrefix("h"), let digit = name.last?.wholeNumberValue, (1...6).contains(digit)
        else {
            return nil
        }
        return digit
    }
}
