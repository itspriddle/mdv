/// The raw-HTML allowlist used by `HTMLSanitizer`.
///
/// Modeled on GitHub's html-pipeline `SanitizationFilter::DEFAULT_CONFIG` and Selma's
/// `VALID_PROTOCOLS`, checked against upstream on 2026-11-06:
///
/// - https://github.com/gjtorikian/html-pipeline/blob/c99d76dbfe817598387c371af342e25abdccd363/lib/html_pipeline/sanitization_filter.rb
/// - https://github.com/gjtorikian/selma/blob/7c87013d89dec5814a53326a6701ecb40603646a/lib/selma/sanitizer/config/default.rb
///
/// Deviations from upstream, all stricter:
///
/// - The URL-valued `action` global attribute is dropped (forms are never allowed).
/// - `source[srcset]` is checked against the `img[src]` protocols (upstream does not check it).
/// - Table parts, list items, and definition terms are kept only inside a matching open raw
///   `table`, `ul`/`ol`, or `dl`, so a stray `<td>` or `<li>` can't restructure the Markdown
///   container it appears in (see `requiredAncestors`).
/// - Script-like and foreign-content elements are removed with their content (see
///   `contentDroppingElements`) instead of only having the tag removed.
enum HTMLSanitizerPolicy {
    /// Elements that may appear in the output.
    static let elements: Set<String> = [
        "h1", "h2", "h3", "h4", "h5", "h6", "br", "b", "i", "strong", "em", "a", "pre", "code", "img", "tt",
        "div", "ins", "del", "sup", "sub", "p", "picture", "ol", "ul", "table", "thead", "tbody", "tfoot",
        "blockquote", "dl", "dt", "dd", "kbd", "q", "samp", "var", "hr", "ruby", "rt", "rp", "li", "tr", "td",
        "th", "s", "strike", "summary", "details", "caption", "figure", "figcaption", "abbr", "bdo", "cite",
        "dfn", "mark", "small", "source", "span", "time", "wbr",
    ]

    /// Allowed elements that have no end tag and are never pushed on the open-element stack.
    static let voidElements: Set<String> = ["br", "hr", "img", "source", "wbr"]

    /// Attributes allowed on every allowed element.
    static let globalAttributes: Set<String> = [
        "abbr", "accept", "accept-charset", "accesskey", "align", "alt", "aria-describedby", "aria-hidden",
        "aria-label", "aria-labelledby", "axis", "border", "char", "charoff", "charset", "checked", "clear",
        "cols", "colspan", "compact", "coords", "datetime", "dir", "disabled", "enctype", "for", "frame",
        "headers", "height", "hreflang", "hspace", "id", "ismap", "label", "lang", "maxlength", "media",
        "method", "multiple", "name", "nohref", "noshade", "nowrap", "open", "progress", "prompt", "readonly",
        "rel", "rev", "role", "rows", "rowspan", "rules", "scope", "selected", "shape", "size", "span", "start",
        "summary", "tabindex", "title", "type", "usemap", "valign", "value", "width", "itemprop",
    ]

    /// Attributes allowed only on specific elements.
    static let elementAttributes: [String: Set<String>] = [
        "a": ["href"],
        "img": ["src", "longdesc", "loading", "alt"],
        "div": ["itemscope", "itemtype"],
        "blockquote": ["cite"],
        "del": ["cite"],
        "ins": ["cite"],
        "q": ["cite"],
        "source": ["srcset"],
    ]

    /// Schemes allowed in URL-valued attributes, by element and attribute. Relative URLs
    /// (including `#fragment`) are always allowed; see `URLSchemePolicy`.
    static let urlSchemes: [String: [String: Set<String>]] = [
        "a": ["href": linkSchemes],
        "blockquote": ["cite": resourceSchemes],
        "del": ["cite": resourceSchemes],
        "ins": ["cite": resourceSchemes],
        "q": ["cite": resourceSchemes],
        "img": ["src": resourceSchemes, "longdesc": resourceSchemes],
        "source": ["srcset": resourceSchemes],
    ]

    /// `id`/`name` values get this prefix, as on GitHub, so raw HTML can't collide with (or
    /// clobber) the ids mdv generates for headings and footnotes.
    static let userContentPrefix = "user-content-"
    static let prefixedAttributes: Set<String> = ["id", "name"]

    /// Elements whose content is text up to their end tag (raw text and RCDATA in the HTML
    /// parser). They are removed together with that content.
    static let rawTextElements: Set<String> = [
        "script", "style", "iframe", "textarea", "title", "noscript", "xmp", "noembed", "noframes", "plaintext",
    ]

    /// Other elements removed together with their content. Unknown elements not listed here
    /// are removed but their content is kept.
    static let contentDroppingElements: Set<String> = [
        "object", "embed", "applet", "form", "template", "select", "svg", "math", "frameset",
    ]

    /// Allowed elements kept only while one of the listed elements is open in the same Markdown
    /// container; otherwise the tag is dropped (its content is kept).
    static let requiredAncestors: [String: Set<String>] = [
        "li": ["ul", "ol"],
        "dt": ["dl"],
        "dd": ["dl"],
        "caption": ["table"],
        "thead": ["table"],
        "tbody": ["table"],
        "tfoot": ["table"],
        "tr": ["table"],
        "td": ["tr"],
        "th": ["tr"],
    ]

    static func allowsAttribute(_ attribute: String, on element: String) -> Bool {
        // Event handlers and inline styles are never allowed, whatever the lists above say.
        if attribute.hasPrefix("on") || attribute == "style" {
            return false
        }
        return globalAttributes.contains(attribute) || elementAttributes[element]?.contains(attribute) == true
    }

    private static let linkSchemes: Set<String> = ["http", "https", "mailto"]
    private static let resourceSchemes: Set<String> = ["http", "https"]
}
