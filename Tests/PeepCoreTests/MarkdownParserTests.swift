import Testing

@testable import MdvCore

/// All node kinds in document order (pre-order), without recursion.
private func kinds(_ root: MarkdownNode) -> [MarkdownNode.Kind] {
    var result: [MarkdownNode.Kind] = []
    var stack = [root]
    while let node = stack.popLast() {
        result.append(node.kind)
        stack.append(contentsOf: node.children.reversed())
    }
    return result
}

private func depth(_ root: MarkdownNode) -> Int {
    var maximum = 0
    var stack = [(root, 1)]
    while let (node, level) = stack.popLast() {
        maximum = max(maximum, level)
        stack.append(contentsOf: node.children.map { ($0, level + 1) })
    }
    return maximum
}

@Suite("MarkdownParser")
struct MarkdownParserTests {
    let parser = MarkdownParser()

    @Test("builds a tree of CommonMark block nodes")
    func blocks() {
        let tree = parser.parse("# H\n\n> q\n\n- a\n\n```js x\ncode\n```\n\n<div>\n</div>\n\n---\n")
        #expect(
            tree.children.map(\.kind) == [
                .heading(level: 1),
                .blockQuote,
                .list(ListInfo(isOrdered: false, start: 0, delimiter: .none, isTight: true)),
                .codeBlock(CodeBlock(info: "js x", literal: "code\n", isFenced: true)),
                .htmlBlock("<div>\n</div>\n"),
                .thematicBreak,
            ])
    }

    @Test("builds CommonMark inline nodes")
    func inlines() {
        let tree = parser.parse("*e* **s** `c` <b> [l](/u \"t\") ![i](/p)\\\nx\ny")
        #expect(
            kinds(tree) == [
                .document, .paragraph,
                .emphasis, .text("e"), .text(" "),
                .strong, .text("s"), .text(" "),
                .code("c"), .text(" "),
                .htmlInline("<b>"), .text(" "),
                .link(destination: "/u", title: "t"), .text("l"), .text(" "),
                .image(source: "/p", title: nil), .text("i"),
                .lineBreak, .text("x"), .softBreak, .text("y"),
            ])
    }

    @Test("ordered list info")
    func orderedList() {
        let tree = parser.parse("7) a\n\n8) b")
        #expect(
            tree.children.first?.kind
                == .list(ListInfo(isOrdered: true, start: 7, delimiter: .parenthesis, isTight: false)))
    }

    @Test("code block language is the first word of the info string")
    func codeLanguage() {
        #expect(CodeBlock(info: "swift title=x", literal: "", isFenced: true).language == "swift")
        #expect(CodeBlock(info: "", literal: "", isFenced: false).language == nil)
    }

    @Test("source ranges use 1-based lines in the parsed text")
    func sourceRanges() {
        let tree = parser.parse("first\n\n## Second\n\n- a\n- b\n")
        #expect(tree.children.map { $0.sourceRange?.start.line } == [1, 3, 5])
        let list = tree.children[2]
        #expect(
            list.sourceRange
                == SourceRange(start: SourcePosition(line: 5, column: 1), end: SourcePosition(line: 6, column: 3)))
        #expect(list.children.map { $0.sourceRange?.start.line } == [5, 6])
    }

    @Test("smart punctuation is never applied")
    func noSmart() {
        #expect(kinds(parser.parse("\"x\" -- ...")).contains(.text("\"x\" -- ...")))
    }

    @Test("pathological nesting is capped at maximumNestingDepth")
    func nestingCap() {
        let tree = parser.parse(String(repeating: "> ", count: 10_000) + "deep")
        #expect(depth(tree) > 100)
        #expect(depth(tree) <= MarkdownParser.maximumNestingDepth + 2)
        #expect(kinds(tree).contains(.text("deep")))
    }
}

@Suite("MarkdownParser: extensions")
struct MarkdownParserExtensionTests {
    @Test("extensions are off by default")
    func offByDefault() {
        let tree = MarkdownParser().parse("| a |\n|---|\n| 1 |\n\n~~s~~")
        #expect(!kinds(tree).contains(.strikethrough))
        #expect(!kinds(tree).contains(.table(alignments: [.none])))
    }

    @Test("table nodes carry alignment and header flags")
    func table() {
        let tree = MarkdownParser(extensions: [.table]).parse("| a | b | c | d |\n|:--|:-:|--:|---|\n| 1 | 2 | 3 | 4 |")
        let table = tree.children.first
        #expect(table?.kind == .table(alignments: [.left, .center, .right, .none]))
        #expect(table?.children.map(\.kind) == [.tableRow(isHeader: true), .tableRow(isHeader: false)])
        #expect(
            table?.children.last?.children.map(\.kind) == [
                .tableCell(alignment: .left, isHeader: false),
                .tableCell(alignment: .center, isHeader: false),
                .tableCell(alignment: .right, isHeader: false),
                .tableCell(alignment: .none, isHeader: false),
            ])
        #expect(table?.children.first?.children.first?.kind == .tableCell(alignment: .left, isHeader: true))
    }

    @Test("strikethrough, autolinks, and task items")
    func inlineExtensions() {
        let tree = MarkdownParser(extensions: [.strikethrough, .autolink, .taskList])
            .parse("~~s~~ www.example.com\n\n- [x] done\n- [ ] todo")
        let all = kinds(tree)
        #expect(all.contains(.strikethrough))
        #expect(all.contains(.link(destination: "http://www.example.com", title: nil)))
        #expect(all.contains(.taskItem(isChecked: true)))
        #expect(all.contains(.taskItem(isChecked: false)))
    }

    @Test("footnote references and definitions")
    func footnotes() {
        let tree = MarkdownParser(extensions: [.footnotes]).parse("a[^b] c[^b] d[^z]\n\n[^z]: Z\n[^b]: B\n")
        let all = kinds(tree)
        #expect(all.contains(.footnoteReference(label: "b", number: 1, referenceIndex: 1)))
        #expect(all.contains(.footnoteReference(label: "b", number: 1, referenceIndex: 2)))
        #expect(all.contains(.footnoteReference(label: "z", number: 2, referenceIndex: 1)))
        #expect(
            tree.children.dropFirst().map(\.kind) == [
                .footnoteDefinition(label: "b", number: 1, referenceCount: 2),
                .footnoteDefinition(label: "z", number: 2, referenceCount: 1),
            ])
    }

    @Test("footnotes take cmark's source-order numbers and counts, even when referenced from notes")
    func footnotesReferencedFromDefinitions() {
        // cmark numbers in source order: the reference to d inside e's definition comes first.
        let tree = MarkdownParser(extensions: [.footnotes]).parse("[^d]: D\n\n[^e]: see [^d] [^E]\n\nx[^e]\n")
        let all = kinds(tree)
        #expect(all.contains(.footnoteReference(label: "d", number: 1, referenceIndex: 1)))
        #expect(all.contains(.footnoteReference(label: "e", number: 2, referenceIndex: 1)))
        #expect(all.contains(.footnoteReference(label: "e", number: 2, referenceIndex: 2)))
        #expect(
            tree.children.dropFirst().map(\.kind) == [
                .footnoteDefinition(label: "d", number: 1, referenceCount: 1),
                .footnoteDefinition(label: "e", number: 2, referenceCount: 2),
            ])
    }
}
