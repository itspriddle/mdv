import Foundation
import MdvCore
import Observation
import WebKit

/// What a window's link status overlay shows: where the hovered link goes, or a short message
/// about the last link followed (blocked, missing file). Like Safari's status bar.
@MainActor
@Observable
final class LinkStatus {
    /// Where the hovered (or focused) link goes; `nil` when no link is hovered.
    private(set) var hoverText: String?
    /// A transient message, shown until it expires or the next one replaces it.
    private(set) var message: String?

    /// The text to show: a message wins over the hover text.
    var text: String? {
        message ?? hoverText
    }

    /// How long a message stays up.
    static let messageDuration: Duration = .seconds(4)

    /// Longest href handled; longer ones are truncated for display (the overlay truncates
    /// further). Bounds the work a hostile document can cause.
    static let maximumHrefLength = 4096

    @ObservationIgnored private var messageTask: Task<Void, Never>?

    /// Shows where `href` (a hovered link's resolved URL, from `LinkHover.js`) goes under
    /// `context`, or clears the hover text when `href` is empty.
    func hover(href: String, context: LinkContext) {
        guard !href.isEmpty else {
            hoverText = nil
            return
        }
        let href = String(href.prefix(Self.maximumHrefLength))
        guard let url = URL(string: href) else {
            hoverText = "Blocked link"
            return
        }
        hoverText = LinkPolicy.statusText(for: LinkPolicy.action(for: url, in: context))
    }

    func show(message: String) {
        self.message = message
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: Self.messageDuration)
            guard !Task.isCancelled else {
                return
            }
            self?.message = nil
        }
    }

    func clear() {
        messageTask?.cancel()
        message = nil
        hoverText = nil
    }
}

/// Receives `LinkHover.js` messages. Registered in `AppScripts.world` only, so the page can't
/// post to it; even so, the body is treated as untrusted display text. Holds its coordinator
/// weakly (the user content controller retains its handlers).
@MainActor
final class LinkHoverMessageHandler: NSObject, WKScriptMessageHandler {
    /// The message handler name `LinkHover.js` posts to.
    static let name = "linkHover"

    weak var coordinator: WebViewCoordinator?

    init(coordinator: WebViewCoordinator) {
        self.coordinator = coordinator
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard message.frameInfo.isMainFrame, message.world.name == AppScripts.world.name,
            let href = message.body as? String, let coordinator
        else {
            return
        }
        coordinator.linkStatus.hover(href: href, context: coordinator.linkContext)
    }
}
