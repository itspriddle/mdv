/// Renders frontmatter for `FrontmatterDisplay.table`. Every key and value is untrusted and is
/// written with `HTMLOutput.text` (escaped); only the surrounding markup is literal.
enum FrontmatterHTML {
    /// Parsed YAML becomes a `<table class="frontmatter">` of top-level keys; TOML becomes a code
    /// block. Returns nothing for YAML that is empty or failed to parse (it stays hidden).
    static func render(_ frontmatter: Frontmatter, into output: inout HTMLOutput) {
        switch frontmatter.format {
        case .toml:
            output.raw("<pre class=\"frontmatter\"><code class=\"language-toml\">")
            output.text(frontmatter.raw)
            output.raw("</code></pre>\n")
        case .yaml:
            guard let entries = frontmatter.entries, !entries.isEmpty else {
                return
            }
            table(entries, className: "frontmatter", into: &output)
        }
    }

    /// Nesting is bounded by `YAMLFrontmatter.maximumDepth`, so recursion here is shallow.
    private static func table(_ entries: [FrontmatterEntry], className: String?, into output: inout HTMLOutput) {
        output.raw(className.map { "<table class=\"\($0)\">\n" } ?? "<table>\n")
        output.raw("<tbody>\n")
        for entry in entries {
            output.raw("<tr>\n<th>")
            output.text(entry.key)
            output.raw("</th>\n<td>")
            value(entry.value, into: &output)
            output.raw("</td>\n</tr>\n")
        }
        output.raw("</tbody>\n</table>\n")
    }

    /// Scalars as text, arrays as comma-separated lists, mappings as nested tables.
    private static func value(_ value: FrontmatterValue, into output: inout HTMLOutput) {
        switch value {
        case .null:
            break
        case .scalar(let text):
            output.text(text)
        case .array(let items):
            for (index, item) in items.enumerated() {
                if index > 0 {
                    output.raw(", ")
                }
                self.value(item, into: &output)
            }
        case .table(let entries):
            output.raw("\n")
            table(entries, className: nil, into: &output)
        }
    }
}
