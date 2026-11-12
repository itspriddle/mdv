/// Named character references whose value is entirely ASCII, generated from the WHATWG
/// table at https://html.spec.whatwg.org/entities.json (fetched 2026-11-06).
///
/// Every other named reference produces at least one non-ASCII character; the only mixed ones
/// (`&bne;`, `&nvgt;`, `&nvlt;`) start with `=`, `>`, or `<`, none of which can appear in a URL
/// scheme. That is why `AttributeValue` only needs to decode these to judge URL schemes.
enum HTMLEntities {
    /// Name (without `&` and `;`) to value, for references written with a `;`.
    static let asciiValued: [String: String] = [
        "AMP": "&",
        "DiacriticalGrave": "`",
        "GT": ">",
        "Hat": "^",
        "LT": "<",
        "NewLine": "\n",
        "QUOT": "\"",
        "Tab": "\t",
        "UnderBar": "_",
        "VerticalLine": "|",
        "amp": "&",
        "apos": "'",
        "ast": "*",
        "bsol": "\\",
        "colon": ":",
        "comma": ",",
        "commat": "@",
        "dollar": "$",
        "equals": "=",
        "excl": "!",
        "fjlig": "fj",
        "grave": "`",
        "gt": ">",
        "lbrace": "{",
        "lbrack": "[",
        "lcub": "{",
        "lowbar": "_",
        "lpar": "(",
        "lsqb": "[",
        "lt": "<",
        "midast": "*",
        "num": "#",
        "percnt": "%",
        "period": ".",
        "plus": "+",
        "quest": "?",
        "quot": "\"",
        "rbrace": "}",
        "rbrack": "]",
        "rcub": "}",
        "rpar": ")",
        "rsqb": "]",
        "semi": ";",
        "sol": "/",
        "verbar": "|",
        "vert": "|",
    ]

    /// Legacy references that browsers also decode without a `;`.
    static let legacyASCIIValued: [String: Unicode.Scalar] = [
        "AMP": "&",
        "GT": ">",
        "LT": "<",
        "QUOT": "\"",
        "amp": "&",
        "gt": ">",
        "lt": "<",
        "quot": "\"",
    ]
}
