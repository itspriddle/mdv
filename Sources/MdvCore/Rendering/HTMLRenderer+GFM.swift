// GFM extension rendering for `HTMLRenderer`: tables, strikethrough, task lists, and footnotes.

extension HTMLRenderer {
    func renderExtensionEnter(_ node: MarkdownNode, _ context: Context, into output: inout HTMLOutput) {
        switch node.kind {
        case .table:
            openBlock("table", node, into: &output)
        case .tableRow(let isHeader):
            output.newlineIfNeeded()
            if isHeader {
                output.raw("<thead>\n")
            } else if context.opensTableBody {
                output.raw("<tbody>\n")
            }
            openBlock("tr", node, into: &output)
        case .tableCell(let alignment, let isHeader):
            output.newlineIfNeeded()
            output.raw(isHeader ? "<th" : "<td")
            switch alignment {
            case .left: output.raw(" align=\"left\"")
            case .center: output.raw(" align=\"center\"")
            case .right: output.raw(" align=\"right\"")
            case .none: break
            }
            output.raw(">")
        case .strikethrough:
            output.raw("<del>")
        case .taskItem(let isChecked):
            renderTaskItemStart(node, isChecked: isChecked, into: &output)
        case .footnoteReference(let label, let number, let referenceIndex):
            renderFootnoteReference(label: label, number: number, referenceIndex: referenceIndex, into: &output)
        case .footnoteDefinition(let label, _, _):
            renderFootnoteDefinitionStart(
                node, label: label, opensSection: context.opensFootnoteSection, into: &output)
        default:
            break
        }
    }

    func renderExtensionExit(_ node: MarkdownNode, _ context: Context, into output: inout HTMLOutput) {
        switch node.kind {
        case .table:
            if node.children.contains(where: \.kind.isTableBodyRow) {
                output.newlineIfNeeded()
                output.raw("</tbody>\n")
            }
            output.newlineIfNeeded()
            output.raw("</table>\n")
        case .tableRow(let isHeader):
            output.newlineIfNeeded()
            output.raw(isHeader ? "</tr>\n</thead>" : "</tr>")
        case .tableCell(_, let isHeader):
            output.raw(isHeader ? "</th>" : "</td>")
        case .strikethrough:
            output.raw("</del>")
        case .taskItem:
            output.raw("</li>\n")
        case .footnoteDefinition(let label, let number, let referenceCount):
            // A trailing paragraph already holds the back-references.
            if node.children.last?.kind != .paragraph {
                writeFootnoteBackrefs(
                    FootnoteBackrefs(label: label, number: number, referenceCount: referenceCount), into: &output)
                output.newlineIfNeeded()
            }
            output.raw("</li>\n")
        default:
            break
        }
    }

    private func renderTaskItemStart(_ node: MarkdownNode, isChecked: Bool, into output: inout HTMLOutput) {
        output.newlineIfNeeded()
        switch options.gfmMarkup {
        case .github:
            output.raw("<li class=\"task-list-item\"")
            writeSourceLine(of: node, into: &output)
            output.raw(">")
            // A leading paragraph writes the checkbox itself (`Context.taskCheckbox`).
            if node.children.first?.kind != .paragraph {
                writeTaskCheckbox(isChecked: isChecked, into: &output)
            }
        case .cmark:
            openBlock("li", node, into: &output)
            output.raw(
                isChecked
                    ? "<input type=\"checkbox\" checked=\"\" disabled=\"\" /> "
                    : "<input type=\"checkbox\" disabled=\"\" /> ")
        }
    }

    /// GitHub's task list checkbox and the space after it (the item's text starts after the
    /// `[ ] ` marker). Always disabled: mdv is a viewer.
    func writeTaskCheckbox(isChecked: Bool, into output: inout HTMLOutput) {
        output.raw(
            isChecked
                ? "<input type=\"checkbox\" disabled=\"\" class=\"task-list-item-checkbox\" "
                    + "aria-label=\"Completed task\" checked=\"\"> "
                : "<input type=\"checkbox\" disabled=\"\" class=\"task-list-item-checkbox\" "
                    + "aria-label=\"Incomplete task\"> ")
    }

    /// A footnote reference. Labels are user text: ids and hrefs percent-encode them like cmark
    /// (`houdini_escape_href`), so they can't break out of the attribute.
    private func renderFootnoteReference(label: String, number: Int, referenceIndex: Int, into output: inout HTMLOutput)
    {
        output.raw(options.gfmMarkup == .github ? "<sup><a href=\"#fn-" : "<sup class=\"footnote-ref\"><a href=\"#fn-")
        output.url(label)
        output.raw("\" id=\"fnref-")
        output.url(label)
        if referenceIndex > 1 {
            output.raw("-\(referenceIndex)")
        }
        output.raw(
            options.gfmMarkup == .github
                ? "\" data-footnote-ref=\"\" aria-describedby=\"footnote-label\">" : "\" data-footnote-ref>")
        output.raw("\(number)</a></sup>")
    }

    /// Footnote definitions are the document's last children, in number order. The first opens
    /// the section; the document closes it.
    private func renderFootnoteDefinitionStart(
        _ node: MarkdownNode, label: String, opensSection: Bool, into output: inout HTMLOutput
    ) {
        output.newlineIfNeeded()
        if opensSection {
            output.raw(
                options.gfmMarkup == .github
                    ? "<section data-footnotes=\"\" class=\"footnotes\">"
                        + "<h2 id=\"footnote-label\" class=\"sr-only\">Footnotes</h2>\n<ol>\n"
                    : "<section class=\"footnotes\" data-footnotes>\n<ol>\n")
        }
        output.raw("<li id=\"fn-")
        output.url(label)
        output.raw("\"")
        writeSourceLine(of: node, into: &output)
        output.raw(">\n")
    }

    /// One back-link per reference to the footnote; the second and later are suffixed `-2`, ...
    func writeFootnoteBackrefs(_ backrefs: FootnoteBackrefs, into output: inout HTMLOutput) {
        for index in 1...max(backrefs.referenceCount, 1) {
            let suffix = index > 1 ? "-\(index)" : ""
            if index > 1 {
                output.raw(" ")
            }
            output.raw("<a href=\"#fnref-")
            output.url(backrefs.label)
            output.raw(suffix)
            switch options.gfmMarkup {
            case .github:
                output.raw("\" data-footnote-backref=\"\" aria-label=\"Back to reference \(backrefs.number)\(suffix)\"")
                output.raw(" class=\"data-footnote-backref\">↩")
                if index > 1 {
                    output.raw("<sup>\(index)</sup>")
                }
            case .cmark:
                output.raw("\" class=\"footnote-backref\" data-footnote-backref data-footnote-backref-idx=\"")
                output.raw(
                    "\(backrefs.number)\(suffix)\" aria-label=\"Back to reference \(backrefs.number)\(suffix)\">↩")
                if index > 1 {
                    output.raw("<sup class=\"footnote-ref\">\(index)</sup>")
                }
            }
            output.raw("</a>")
        }
    }
}

extension MarkdownNode.Kind {
    var isTableBodyRow: Bool {
        self == .tableRow(isHeader: false)
    }

    var isTaskItem: Bool {
        if case .taskItem = self { true } else { false }
    }

    var isFootnoteDefinition: Bool {
        if case .footnoteDefinition = self { true } else { false }
    }
}

/// The back-links written at the end of a footnote: one per reference to it.
struct FootnoteBackrefs {
    var label: String
    var number: Int
    var referenceCount: Int
}
