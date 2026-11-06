import MdvCore

@testable import MdvApp

/// Pages for `RemoteImageNetworkTests`: every way a document or a page can load something.
extension RemoteImageNetworkTests {
    /// A Markdown document using every way to write a remote image, at `http` (plain) and
    /// `https` (TLS) servers.
    static func remoteImageDocument(http: LoopbackServer, https: LoopbackServer) -> String {
        """
        # Remote images

        ![md http](\(http.url("/md.png"))) ![md https](\(https.url("/md.png", https: true)))
        ![ref][badge] [![linked](\(https.url("/linked.svg", https: true)))](https://example.invalid)
        ![titled](\(http.url("/titled.png")) "Title") ![scheme-relative](//127.0.0.1:\(http.port)/rel.png)

        [badge]: \(https.url("/ref.svg", https: true))

        <img src="\(http.url("/raw.png"))" alt="raw http" width="20" height="20">
        <img src="\(https.url("/raw.png", https: true))" alt="raw https">
        <img src="h&#116;tp://127.0.0.1:\(http.port)/encoded.png" alt="encoded">
        <picture><source srcset="\(https.url("/source.png", https: true)) 2x">\
        <img src="\(http.url("/fallback.png"))"></picture>
        <p><img src="\(http.url("/nested.png"))" alt="nested"></p>

        | Table |
        | --- |
        | ![cell](\(http.url("/cell.png"))) |

        Footnote.[^1]

        [^1]: ![note](\(https.url("/note.png", https: true)))

        <iframe src="\(http.url("/frame"))"></iframe>
        <video src="\(http.url("/video.mp4"))" poster="\(http.url("/poster.png"))"></video>
        <link rel="stylesheet" href="\(http.url("/style.css"))">
        <style>@import url("\(http.url("/import.css"))"); body { background: url("\(http.url("/bg.png"))"); }</style>
        <div style="background-image: url('\(http.url("/inline-bg.png"))')">styled</div>
        <object data="\(http.url("/object"))"></object><embed src="\(http.url("/embed"))">
        <svg><image href="\(http.url("/svg.png"))"/></svg>
        <input type="image" src="\(http.url("/input.png"))">
        """
    }

    /// Head and body markup that loads images from `url(path)` in every way a page can: the
    /// loads `img-src` governs.
    static func imageLoads(_ url: (String) -> String) -> (head: String, body: String) {
        (
            """
            <link rel="icon" href="\(url("/icon.png"))">
            <link rel="preload" as="image" href="\(url("/preload.png"))">
            <style>
            body { background: url("\(url("/body-bg.png"))"); }
            .cursor { cursor: url("\(url("/cursor.png"))"), auto; }
            </style>
            """,
            """
            <p class="cursor">cursor</p>
            <img src="\(url("/img.png"))" alt="img">
            <img srcset="\(url("/srcset.png")) 1x" alt="srcset">
            <picture><source srcset="\(url("/source.png"))"><img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" \
            alt="picture"></picture>
            <svg width="10" height="10"><image href="\(url("/svg-image.png"))" width="10" height="10"/></svg>
            <input type="image" src="\(url("/input.png"))">
            <video poster="\(url("/poster.png"))"></video>
            <table background="\(url("/table-bg.png"))"><tr><td>cell</td></tr></table>
            <div style="background-image: url('\(url("/inline-bg.png"))'); width: 10px; height: 10px"></div>
            """
        )
    }

    /// Head and body markup that loads everything else: styles, fonts, frames, plugins, media,
    /// prefetches.
    static func otherLoads(_ url: (String) -> String) -> (head: String, body: String) {
        (
            """
            <link rel="stylesheet" href="\(url("/link.css"))">
            <link rel="prefetch" href="\(url("/prefetch"))">
            <style>
            @import url("\(url("/import.css"))");
            @font-face { font-family: Remote; src: url("\(url("/font.woff2"))"); }
            .font { font-family: Remote; }
            </style>
            """,
            """
            <p class="font">Text in the remote font.</p>
            <iframe src="\(url("/iframe"))"></iframe>
            <object data="\(url("/object"))"></object>
            <embed src="\(url("/embed"))">
            <video src="\(url("/video.mp4"))" preload="auto"></video>
            <audio src="\(url("/audio.mp3"))" preload="auto"></audio>
            """
        )
    }

    /// Hand-written HTML (never sanitized) under `csp`, or with no CSP for the control.
    static func page(csp: ContentSecurityPolicy?, _ parts: [(head: String, body: String)]) -> String {
        let meta = csp.map { "<meta http-equiv=\"Content-Security-Policy\" content=\"\($0.header)\">" } ?? ""
        return """
            <!doctype html><html><head><meta charset="utf-8">\(meta)
            \(parts.map(\.head).joined(separator: "\n"))
            </head><body>
            \(parts.map(\.body).joined(separator: "\n"))
            </body></html>
            """
    }

    /// Every kind of load, at plain HTTP on `server`.
    static func hostilePage(csp: ContentSecurityPolicy?, server: LoopbackServer) -> String {
        let url = { (path: String) in server.url(path) }
        return page(csp: csp, [imageLoads(url), otherLoads(url)])
    }
}
