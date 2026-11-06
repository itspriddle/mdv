import cmark_gfm

/// Optional syntax on top of CommonMark. `MarkdownParser` enables these per `RenderOptions`.
///
/// Most map to a cmark-gfm syntax extension attached to the parser; footnotes are a parser
/// option instead. The `tagfilter` extension is deliberately absent: raw HTML is handled by mdv's
/// own sanitizer (#7).
public enum MarkdownExtension: String, CaseIterable, Sendable {
    case table
    case strikethrough
    case autolink
    case taskList
    case footnotes

    /// GitHub Flavored Markdown as github.com renders it: every extension above. `RenderOptions`
    /// uses this by default.
    public static let gfm: Set<MarkdownExtension> = [.table, .strikethrough, .autolink, .taskList, .footnotes]

    /// The name registered by `cmark_gfm_core_extensions_ensure_registered()`, if any.
    var syntaxExtensionName: String? {
        switch self {
        case .table: "table"
        case .strikethrough: "strikethrough"
        case .autolink: "autolink"
        case .taskList: "tasklist"
        case .footnotes: nil
        }
    }

    /// Extra `CMARK_OPT_*` bits this extension needs.
    var parserOptions: Int32 {
        switch self {
        case .footnotes: CMARK_OPT_FOOTNOTES
        case .table, .strikethrough, .autolink, .taskList: 0
        }
    }
}
