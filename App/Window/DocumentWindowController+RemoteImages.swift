import AppKit

extension DocumentWindowController {
    /// The page this window shows for the document's current content: remote images blocked,
    /// or `https:` images loaded once the window opted in. Live reloads go through this too, so
    /// the opt-in survives them.
    var displayedPage: RenderedPage? {
        markdownDocument?.content?.page(allowingRemoteImages: remoteImages.isAllowed)
    }

    /// The remote images bar's Load button: opts this window in and shows the page again. The
    /// new page has another CSP, so `display()` loads it fully (keeping the reading position)
    /// instead of swapping content in place.
    @objc func loadRemoteImages(_ sender: Any?) {
        guard !remoteImages.isAllowed else {
            return
        }
        remoteImages.allow()
        documentContentDidChange()
    }
}
