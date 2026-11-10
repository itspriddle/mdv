/// The render-time highlighting pass: runs a `SyntaxHighlighter` over a tree's fenced code
/// blocks and stores validated markup on each block for `HTMLRenderer` to write.
///
/// - Only blocks whose info string names a language (its first word) are highlighted; the
///   highlighter resolves the name and returns `nil` for languages it doesn't know.
/// - Blocks larger than `maximumBlockBytes` are skipped, and at most `documentBudgetBytes` of
///   code is highlighted per document: a block that doesn't fit in what's left of the budget is
///   skipped (a later, smaller one may still fit). Each call is charged at least
///   `minimumChargeBytes`, so many tiny blocks can't run up unbounded calls. JavaScriptCore has
///   no public execution time limit, so these caps bound the work instead (highlight.js runs at
///   roughly 1 MB/s, so the budget is about 200 ms of highlighting in the worst case).
/// - Output is accepted only through `HighlightValidator`; rejected output, unknown languages,
///   and skipped blocks render as plain escaped code.
struct CodeHighlighting {
    static let maximumBlockBytes = 128 * 1024
    static let documentBudgetBytes = 256 * 1024
    static let minimumChargeBytes = 512

    let highlighter: any SyntaxHighlighter
    private var remainingBudget = Self.documentBudgetBytes

    init(highlighter: any SyntaxHighlighter) {
        self.highlighter = highlighter
    }

    /// Validated highlighted markup for `block`, or `nil` to render it plain.
    mutating func highlight(_ block: CodeBlock) -> String? {
        guard let language = block.language else {
            return nil
        }
        let size = block.literal.utf8.count
        let charge = max(size, Self.minimumChargeBytes)
        guard size <= Self.maximumBlockBytes, charge <= remainingBudget else {
            return nil
        }
        remainingBudget -= charge
        guard let html = highlighter.highlight(block.literal, language: language) else {
            return nil
        }
        return HighlightValidator.validated(html, source: block.literal)
    }

    private struct Frame {
        var node: MarkdownNode
        var nextChild = 0
        var children: [MarkdownNode] = []
        var changed = false

        init(_ node: MarkdownNode) {
            self.node = node
        }
    }

    /// Returns `root` with `CodeBlock.highlightedHTML` set on every block that highlights.
    /// Walks block containers only (code blocks never appear inside inlines), with an explicit
    /// stack, and rebuilds only the containers that changed.
    mutating func apply(to root: MarkdownNode) -> MarkdownNode {
        if case .codeBlock(var block) = root.kind {
            block.highlightedHTML = highlight(block)
            var node = root
            node.kind = .codeBlock(block)
            return node
        }
        var stack = [Frame(root)]
        while let top = stack.indices.last {
            guard stack[top].nextChild < stack[top].node.children.count else {
                let frame = stack.removeLast()
                var node = frame.node
                if frame.changed {
                    node.children = frame.children
                }
                guard !stack.isEmpty else {
                    return node
                }
                stack[stack.count - 1].children.append(node)
                stack[stack.count - 1].changed = stack[stack.count - 1].changed || frame.changed
                continue
            }
            let child = stack[top].node.children[stack[top].nextChild]
            stack[top].nextChild += 1
            switch child.kind {
            case .codeBlock(var block):
                block.highlightedHTML = highlight(block)
                if block.highlightedHTML != nil {
                    var node = child
                    node.kind = .codeBlock(block)
                    stack[top].children.append(node)
                    stack[top].changed = true
                } else {
                    stack[top].children.append(child)
                }
            case let kind where kind.isBlockContainer:
                stack.append(Frame(child))
            default:
                stack[top].children.append(child)
            }
        }
        return root
    }
}
