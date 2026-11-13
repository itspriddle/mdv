import Foundation

/// The number of words a reader sees in a rendered document: the text of paragraphs, headings,
/// lists, tables, block quotes, alerts, footnotes, link and wiki link labels, inline code, and code
/// blocks. Frontmatter (not in the tree), link destinations, image alt text, raw HTML, emoji,
/// footnote reference numbers, and renderer-written labels (alert titles) are not words.
///
/// Words are found with Foundation's word segmentation (`enumerateSubstrings(options: .byWords)`),
/// so punctuation is not a word and scripts without spaces (Chinese, Japanese) are segmented.
public enum WordCount {
    /// The words in `root` (a document, or any subtree). Walk the transformed tree, so wiki
    /// links and emoji are already their own nodes.
    public static func count(in root: MarkdownNode) -> Int {
        let text = visibleText(of: root)
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    /// The text the word count reads: inline text joined as written (`**foo**bar` is one word),
    /// with a separator at every block, table cell, line break, and emoji.
    static func visibleText(of root: MarkdownNode) -> String {
        var text = ""
        var stack = [root]
        while let node = stack.popLast() {
            switch node.kind {
            case .text(let string), .code(let string):
                text += string
            case .codeBlock(let block):
                text += "\n"
                text += block.literal
                continue
            case .image, .htmlBlock, .htmlInline, .footnoteReference:
                continue
            case .emoji, .softBreak, .lineBreak:
                text += " "
                continue
            case .emphasis, .strong, .strikethrough, .link, .attribute, .wikiLink:
                break
            case .document, .blockQuote, .list, .item, .paragraph, .heading, .thematicBreak, .table, .tableRow,
                .tableCell, .taskItem, .footnoteDefinition, .alert:
                text += "\n"
            }
            stack.append(contentsOf: node.children.reversed())
        }
        return text
    }
}
