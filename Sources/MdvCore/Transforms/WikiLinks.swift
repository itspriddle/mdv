/// Turns `[[Page]]`, `[[Page|label]]`, `[[Page#Heading]]`, and `[[#Heading]]` in text into
/// `wikiLink` nodes (#53). An opt-in built-in preprocessor (`RenderOptions.builtInPreprocessors`),
/// independent of the flavor; off by default.
///
/// Syntax:
///
/// - `[[` and `]]` around a target, all in one run of text: never in code spans or blocks, raw
///   HTML, link text, autolinks, or image alt text, and not across emphasis or other markup
///   (`[[a *b*]]` stays literal). The brackets must be written as is: `\[[Page]]`,
///   `[\[Page]]`, `[[Page\]]`, and `&#91;[Page]]` stay literal (`SourceLines`).
/// - The target holds no `[`, `]`, or line break, and is at most 1,024 bytes. Its first `|`
///   starts the label (`[[Page|label]]`); in a table cell write it `\|`. The target's first `#`
///   starts the heading.
/// - Target, page, heading, and label are trimmed of spaces and tabs. An empty target (`[[]]`,
///   `[[ |x]]`, `[[#]]`) stays literal. An empty label means none: the label is the target as
///   written.
///
/// Output: the page goes through the render's `WikiLinkResolver`; a found file links to its
/// path relative to the document (`Page-Name.md`, percent-encoded), plus `#slug` for a heading
/// (`HeadingSlug`, the target's own heading ids). `[[#Heading]]` links to `#slug` in the same
/// document. A page with no resolver, no file, or a name that names nothing (`WikiPage.init?`)
/// renders as missing. The label is text, written escaped by `HTMLRenderer`, so emoji
/// shortcodes in it still convert (emoji run after wiki links).
enum WikiLinks {
    /// Targets longer than this (UTF-8 bytes, between the brackets) stay literal.
    static let maximumTargetBytes = 1024

    /// A `[[…]]` found in a run of text: byte offsets of the whole match and of its inside.
    struct Match: Equatable {
        var range: Range<Int>
        var inner: Range<Int>
    }

    /// The wiki links in `bytes`, left to right, whose brackets `isVerbatim` accepts.
    static func matches(in bytes: [UInt8], isVerbatim: (Int) -> Bool) -> [Match] {
        var matches: [Match] = []
        var index = 0
        while index + 3 < bytes.count {
            guard bytes[index] == openBracket, bytes[index + 1] == openBracket, isVerbatim(index), isVerbatim(index + 1)
            else {
                index += 1
                continue
            }
            let innerStart = index + 2
            var end = innerStart
            while end < bytes.count, end - innerStart <= maximumTargetBytes, bytes[end] != openBracket,
                bytes[end] != closeBracket
            {
                end += 1
            }
            if end + 1 < bytes.count, end > innerStart, end - innerStart <= maximumTargetBytes,
                bytes[end] == closeBracket, bytes[end + 1] == closeBracket, isVerbatim(end), isVerbatim(end + 1)
            {
                matches.append(Match(range: index..<(end + 2), inner: innerStart..<end))
                index = end + 2
            } else {
                index += 1
            }
        }
        return matches
    }

    /// The parts of a target as written between the brackets: the link (without its
    /// destination) and its label, or `nil` when it stays literal.
    static func parse(_ inner: String) -> (link: WikiLink, label: String)? {
        let pipe = inner.firstIndex(of: "|")
        let target = inner[..<(pipe ?? inner.endIndex)].trimmingWikiWhitespace()
        guard !target.isEmpty else {
            return nil
        }
        let hash = target.firstIndex(of: "#")
        let pageName = target[..<(hash ?? target.endIndex)].trimmingWikiWhitespace()
        let heading = hash.map { target[target.index(after: $0)...].trimmingWikiWhitespace() }.flatMap {
            $0.isEmpty ? nil : $0
        }
        guard !pageName.isEmpty || heading != nil else {
            return nil
        }
        let label = pipe.map { inner[inner.index(after: $0)...].trimmingWikiWhitespace() } ?? ""
        let link = WikiLink(
            target: target, page: pageName.isEmpty ? nil : WikiPage(pageName), heading: heading, destination: nil)
        return (link, label.isEmpty ? target : label)
    }

    /// The `href` for `link` once its page resolved to `path` (relative, not encoded), or for a
    /// same-document link (`path` nil and no page): each path part and the slug percent-encoded,
    /// so nothing in a name can add a scheme, query, or fragment.
    static func destination(path: String?, heading: String?) -> String {
        let fragment = heading.map { HeadingSlug.slug(for: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        let encodedPath = path.map {
            $0.split(separator: "/", omittingEmptySubsequences: false).map(encode).joined(separator: "/")
        }
        return (encodedPath ?? "") + (fragment.map { "#" + encode($0) } ?? (encodedPath == nil ? "#" : ""))
    }

    /// Percent-encodes everything but unreserved characters (`A-Z a-z 0-9 - . _ ~`).
    static func encode<S: StringProtocol>(_ part: S) -> String {
        var encoded = ""
        for byte in part.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"),
                UInt8(ascii: "~"):
                encoded.unicodeScalars.append(Unicode.Scalar(byte))
            default:
                encoded += "%" + String(byte, radix: 16, uppercase: true).leftPadded(to: 2)
            }
        }
        return encoded
    }

    static let openBracket = UInt8(ascii: "[")
    static let closeBracket = UInt8(ascii: "]")
}

// MARK: - The pass

extension WikiLinks: MarkdownTreeTransform {
    static func apply(to root: MarkdownNode, context: TransformContext) -> MarkdownNode {
        var pass = WikiLinkPass(source: context.source, resolver: context.wikiLinkResolver)
        return pass.rewrite(root)
    }
}

/// One render's wiki link rewrite (`WikiLinks.apply`): the source lines (built on first use)
/// and resolved pages.
private struct WikiLinkPass {
    let source: String?
    let resolver: (any WikiLinkResolver)?
    private var lines: SourceLines?
    private var destinations: [WikiPage: String?] = [:]

    init(source: String?, resolver: (any WikiLinkResolver)?) {
        self.source = source
        self.resolver = resolver
    }

    private struct Frame {
        var node: MarkdownNode
        var nextChild = 0
        var children: [MarkdownNode] = []

        init(_ node: MarkdownNode) {
            self.node = node
            children.reserveCapacity(node.children.count)
        }
    }

    /// Rebuilds the tree with an explicit stack (no recursion over its depth).
    mutating func rewrite(_ root: MarkdownNode) -> MarkdownNode {
        guard Self.descends(into: root) else {
            return root
        }
        var stack = [Frame(root)]
        while let top = stack.indices.last {
            guard stack[top].nextChild < stack[top].node.children.count else {
                let frame = stack.removeLast()
                var node = frame.node
                node.children = replacingInTextRuns(frame.children)
                guard !stack.isEmpty else {
                    return node
                }
                stack[stack.count - 1].children.append(node)
                continue
            }
            let child = stack[top].node.children[stack[top].nextChild]
            stack[top].nextChild += 1
            if Self.descends(into: child) {
                stack.append(Frame(child))
            } else {
                stack[top].children.append(child)
            }
        }
        return root
    }

    /// Links, autolinks, and images keep their text; leaves have none.
    private static func descends(into node: MarkdownNode) -> Bool {
        switch node.kind {
        case .link, .image, .wikiLink: false
        default: !node.children.isEmpty
        }
    }

    private mutating func replacingInTextRuns(_ children: [MarkdownNode]) -> [MarkdownNode] {
        var result: [MarkdownNode] = []
        result.reserveCapacity(children.count)
        var index = 0
        while index < children.count {
            guard case .text = children[index].kind else {
                result.append(children[index])
                index += 1
                continue
            }
            var end = index
            while end < children.count, case .text = children[end].kind {
                end += 1
            }
            result += replacing(in: children[index..<end])
            index = end
        }
        return result
    }

    /// A run of adjacent text nodes with its wiki links replaced, or the run unchanged.
    private mutating func replacing(in run: ArraySlice<MarkdownNode>) -> [MarkdownNode] {
        var bytes: [UInt8] = []
        for node in run {
            if case .text(let literal) = node.kind {
                bytes += literal.utf8
            }
        }
        guard Self.mayContainLink(bytes) else {
            return Array(run)
        }
        let mask = verbatimMask(of: run)
        let matches = WikiLinks.matches(in: bytes) { mask?[$0] ?? true }
        guard !matches.isEmpty else {
            return Array(run)
        }
        let range = Self.sourceRange(of: run)
        func text(_ offsets: Range<Int>) -> String {
            String(validating: bytes[offsets], as: UTF8.self) ?? ""
        }
        var nodes: [MarkdownNode] = []
        var literalStart = 0
        for match in matches {
            guard let (link, label) = WikiLinks.parse(text(match.inner)) else {
                continue
            }
            if literalStart < match.range.lowerBound {
                nodes.append(MarkdownNode(.text(text(literalStart..<match.range.lowerBound)), sourceRange: range))
            }
            nodes.append(
                MarkdownNode(
                    .wikiLink(resolved(link)), children: [MarkdownNode(.text(label), sourceRange: range)],
                    sourceRange: range))
            literalStart = match.range.upperBound
        }
        guard !nodes.isEmpty else {
            return Array(run)
        }
        if literalStart < bytes.count {
            nodes.append(MarkdownNode(.text(text(literalStart..<bytes.count)), sourceRange: range))
        }
        return nodes
    }

    /// Which bytes of the run were written as is. `nil` (all) for a tree without source
    /// text (`HTMLRenderer.html(for:)`); a node that can't be aligned counts as escaped.
    private mutating func verbatimMask(of run: ArraySlice<MarkdownNode>) -> [Bool]? {
        guard let source else {
            return nil
        }
        if lines == nil {
            lines = SourceLines(source)
        }
        var mask: [Bool] = []
        for node in run {
            guard case .text(let literal) = node.kind else {
                continue
            }
            let aligned = node.sourceRange.flatMap { lines?.verbatimMask(of: literal, at: $0) }
            mask += aligned ?? Array(repeating: false, count: literal.utf8.count)
        }
        return mask
    }

    /// `link` with its destination, asking the resolver once per page.
    private mutating func resolved(_ link: WikiLink) -> WikiLink {
        var link = link
        guard let page = link.page else {
            // No page part at all (`[[#Heading]]`), as opposed to one naming no page.
            if link.target.first == "#" {
                link.destination = WikiLinks.destination(path: nil, heading: link.heading)
            }
            return link
        }
        let path: String?
        if let cached = destinations[page] {
            path = cached
        } else {
            path = resolver?.destination(for: page)
            destinations[page] = .some(path)
        }
        link.destination = path.map { WikiLinks.destination(path: $0, heading: link.heading) }
        return link
    }

    /// Whether `bytes` has a `[[` followed somewhere by `]]` (a cheap first check).
    private static func mayContainLink(_ bytes: [UInt8]) -> Bool {
        guard
            let open = bytes.indices.first(where: {
                $0 + 1 < bytes.count && bytes[$0] == WikiLinks.openBracket && bytes[$0 + 1] == WikiLinks.openBracket
            })
        else {
            return false
        }
        return bytes[(open + 2)...].indices.contains {
            $0 + 1 < bytes.count && bytes[$0] == WikiLinks.closeBracket && bytes[$0 + 1] == WikiLinks.closeBracket
        }
    }

    private static func sourceRange(of run: ArraySlice<MarkdownNode>) -> SourceRange? {
        guard let start = run.first?.sourceRange?.start, let end = run.last?.sourceRange?.end else {
            return nil
        }
        return SourceRange(start: start, end: end)
    }
}

extension String {
    fileprivate func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
