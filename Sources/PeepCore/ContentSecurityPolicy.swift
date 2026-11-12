/// The Content-Security-Policy every rendered page carries (`HTMLDocument`). Scripts, frames,
/// fonts, media, and remote loads are never allowed; styles are inline only. The one thing that
/// varies is where images may come from.
public struct ContentSecurityPolicy: Sendable, Equatable {
    /// CSP source expressions for `img-src`, e.g. `"data:"` or `"peep-doc:"`.
    public var imageSources: [String]

    public init(imageSources: [String]) {
        self.imageSources = imageSources
    }

    /// Standalone HTML (`peep --html`): images from local files and `data:` URLs, so a saved page
    /// still shows the images next to it when opened in a browser.
    public static let standalone = ContentSecurityPolicy(imageSources: ["file:", "data:"])

    /// The app's viewer: images only through the scoped document scheme (`DocumentURLScheme`,
    /// served by the app after `LocalImagePolicy` approves each read) and `data:` URLs. No
    /// `file:`: the web view itself is never given file access.
    public static let viewer = ContentSecurityPolicy(imageSources: ["\(DocumentURLScheme.name):", "data:"])

    /// The viewer after the user opts in to remote images for a window (#20): `.viewer` plus
    /// `https:` images. Never `http:`: cleartext images can be read and swapped on the network,
    /// and the render option (`RemoteImagePolicy.allowHTTPS`) shows them as placeholders.
    /// Frames, fonts, styles, and media stay blocked.
    public static let viewerAllowingRemoteImages = ContentSecurityPolicy(
        imageSources: viewer.imageSources + ["https:"])

    /// The policy as a `<meta http-equiv="Content-Security-Policy">` value.
    public var header: String {
        "default-src 'none'; style-src 'unsafe-inline'; img-src \(imageSources.joined(separator: " "));"
    }
}
