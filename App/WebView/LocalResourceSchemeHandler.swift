import Foundation
import PeepCore
import WebKit

/// Serves one window's `peep-doc` URLs (`DocumentURLScheme`): local images the document
/// references, after `LocalImagePolicy` approves each read. Everything else, including the
/// document URL itself, gets an empty 404 (the page shows its broken-image state; no reasons,
/// listings, or paths are given).
///
/// Created and installed by `WebViewCoordinator`; `scope(toDocumentAt:)` points it at a
/// document. Files are read off the main actor.
@MainActor
final class LocalResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    /// This window's `DocumentURLScheme` host.
    let token = DocumentURLScheme.makeToken()

    /// What is served now. Nil (serve nothing) until a document with a file URL is scoped.
    private(set) var policy: LocalImagePolicy?

    /// Tasks started and not yet finished or stopped. WebKit raises if a stopped task is used.
    private var activeTasks: Set<ObjectIdentifier> = []

    #if DEBUG
        /// Every URL requested, in order (tests check what a page asked for).
        private(set) var requestedURLs: [URL] = []
    #endif

    /// Allows images under the allowed root of the document at `fileURL` (`LocalResourceRoot`),
    /// and returns the URL to load its page at. With no file URL, or a folder that doesn't
    /// exist, nothing is served and the result is nil.
    func scope(toDocumentAt fileURL: URL?) -> URL? {
        guard let fileURL, let policy = LocalImagePolicy(token: token, documentAt: fileURL) else {
            policy = nil
            return nil
        }
        self.policy = policy
        return policy.documentURL(forFileAt: fileURL)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        #if DEBUG
            requestedURLs.append(url)
        #endif
        activeTasks.insert(id)
        let policy = policy
        Task {
            let image = await Task.detached(priority: .userInitiated) { policy?.image(for: url) }.value
            guard activeTasks.remove(id) != nil else {
                return
            }
            Self.respond(to: urlSchemeTask, url: url, with: image)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        activeTasks.remove(ObjectIdentifier(urlSchemeTask))
    }

    private static func respond(to task: any WKURLSchemeTask, url: URL, with image: LocalImage?) {
        var headers = [
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
            "Content-Length": String(image?.data.count ?? 0),
        ]
        if let image {
            headers["Content-Type"] = image.mimeType
        }
        guard
            let response = HTTPURLResponse(
                url: url, statusCode: image == nil ? 404 : 200, httpVersion: "HTTP/1.1", headerFields: headers)
        else {
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        task.didReceive(response)
        if let image {
            task.didReceive(image.data)
        }
        task.didFinish()
    }
}
