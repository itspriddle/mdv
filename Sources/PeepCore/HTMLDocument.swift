/// Wraps a rendered HTML fragment in a complete, locked-down HTML document.
public struct HTMLDocument: Sendable {
    public var title: String
    public var body: String
    /// The page's theme, in the `mdv-theme` layer above the base layer (`ThemeBase`).
    public var theme: Theme
    /// The reader's style controls, in the `mdv-user` layer above the theme (#37).
    public var userStyle: UserStyle
    /// Restrictive by default: no scripts, no remote loads, inline styles, local images only.
    /// The app passes `.viewer`; `mdv --html` keeps `.standalone`.
    public var contentSecurityPolicy: ContentSecurityPolicy

    public init(
        title: String,
        body: String,
        theme: Theme,
        userStyle: UserStyle = .themeDefaults,
        contentSecurityPolicy: ContentSecurityPolicy = .standalone
    ) {
        self.title = title
        self.body = body
        self.theme = theme
        self.userStyle = userStyle
        self.contentSecurityPolicy = contentSecurityPolicy
    }

    public var html: String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy.header)">
        <meta name="color-scheme" content="light dark">
        <title>\(Self.escape(title))</title>
        <style id="\(ThemeLayer.base.name)">
        \(ThemeBase.layerCSS)
        </style>
        <style id="\(ThemeLayer.theme.name)">
        \(theme.layerCSS)
        </style>
        <style id="\(ThemeLayer.user.name)">
        \(userStyle.layerCSS)
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
