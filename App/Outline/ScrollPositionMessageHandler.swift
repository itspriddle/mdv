import WebKit

/// Receives `ScrollPosition.js` reports and passes them to the coordinator's
/// `sectionLineDidChange`. Registered in `AppScripts.world` only, so the page can't post to it;
/// even so, the body is validated: a finite, positive number, else ignored. Holds its
/// coordinator weakly (the user content controller retains its handlers).
@MainActor
final class ScrollPositionMessageHandler: NSObject, WKScriptMessageHandler {
    /// The message handler name `ScrollPosition.js` posts to.
    static let name = "scrollPosition"

    weak var coordinator: WebViewCoordinator?

    init(coordinator: WebViewCoordinator) {
        self.coordinator = coordinator
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard message.frameInfo.isMainFrame, message.world.name == AppScripts.world.name,
            let line = Self.sourceLine(from: message.body), let coordinator
        else {
            return
        }
        coordinator.sectionLineDidChange?(line)
    }

    /// The source line in a message body, if it is one.
    static func sourceLine(from body: Any) -> Double? {
        guard let number = body as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let line = number.doubleValue
        return line.isFinite && line >= 1 ? line : nil
    }
}
