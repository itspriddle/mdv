/// Wraps a rendered HTML fragment in a complete, locked-down HTML document.
public struct HTMLDocument: Sendable {
    /// Restrictive by default: no scripts, no remote loads. Styles are inline, images are local only.
    public static let contentSecurityPolicy =
        "default-src 'none'; style-src 'unsafe-inline'; img-src file: data:;"

    public var title: String
    public var body: String
    public var stylesheet: String

    public init(title: String, body: String, stylesheet: String = DefaultTheme.css) {
        self.title = title
        self.body = body
        self.stylesheet = stylesheet
    }

    public var html: String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(Self.contentSecurityPolicy)">
        <meta name="color-scheme" content="light dark">
        <title>\(Self.escape(title))</title>
        <style>
        \(stylesheet)
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    static func escape(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
