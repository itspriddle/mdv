import AppKit
import WebKit

/// Window restoration (#22). AppKit and `NSDocument` restore the documents, window frames, and
/// tab groups; this adds each window's reading position, as a source line.
///
/// `ScrollPosition.js` reports the position after every scroll, so the state is current when
/// AppKit encodes it (encoding is synchronous; the bridge is async). `DocumentWindow` writes it
/// into the window's own restorable state (a window controller's `encodeRestorableState` isn't
/// part of the window's state, measured in #22). A restored position is applied once the page
/// loads.
extension DocumentWindowController {
    /// The restorable-state key for the reading position (a `Double` source line).
    static let sourceLineStateKey = "mdvSourceLine"

    /// Listens for `ScrollPosition.js` reports. Called once from `init`.
    func installScrollTracking() {
        coordinator.webView.configuration.userContentController.add(
            ScrollPositionMessageHandler(windowController: self), contentWorld: AppScripts.world,
            name: ScrollPositionMessageHandler.name)
    }

    /// A reported reading position: remember it and let AppKit save it.
    func sourceLineDidChange(_ line: Double) {
        guard let line = Self.validSourceLine(line), line != lastSourceLine else {
            return
        }
        lastSourceLine = line
        window?.invalidateRestorableState()
    }

    /// Adds the reading position to the window's restorable state.
    func encodeReadingPosition(with coder: NSCoder) {
        if let lastSourceLine {
            coder.encode(lastSourceLine, forKey: Self.sourceLineStateKey)
        }
    }

    /// Restores the reading position from the window's restorable state.
    func restoreReadingPosition(with coder: NSCoder) {
        guard coder.containsValue(forKey: Self.sourceLineStateKey),
            let line = Self.validSourceLine(coder.decodeDouble(forKey: Self.sourceLineStateKey))
        else {
            return
        }
        lastSourceLine = line
        guard coordinator.hasLoadedPage else {
            pendingSourceLine = line
            return
        }
        Task { [coordinator] in
            try? await coordinator.scroll(toSourceLine: line)
        }
    }

    /// Applies a restored position that arrived before the page loaded. Called after each load.
    func scrollToPendingSourceLine() async {
        guard let line = pendingSourceLine else {
            return
        }
        pendingSourceLine = nil
        try? await coordinator.scroll(toSourceLine: line)
    }

    /// `line` if it is a usable position (finite, at least 1), else nil. Restorable state and
    /// script messages are both treated as untrusted input.
    nonisolated static func validSourceLine(_ line: Double) -> Double? {
        line.isFinite && line >= 1 ? line : nil
    }
}

/// A document window: saves and restores its controller's reading position with its own
/// restorable state.
final class DocumentWindow: NSWindow {
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        (windowController as? DocumentWindowController)?.encodeReadingPosition(with: coder)
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        (windowController as? DocumentWindowController)?.restoreReadingPosition(with: coder)
    }
}

/// Receives `ScrollPosition.js` reports, from the app's content world only.
final class ScrollPositionMessageHandler: NSObject, WKScriptMessageHandler {
    /// The message handler name `ScrollPosition.js` posts to.
    static let name = "scrollPosition"

    private weak var windowController: DocumentWindowController?

    init(windowController: DocumentWindowController) {
        self.windowController = windowController
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard message.frameInfo.isMainFrame, message.world.name == AppScripts.world.name,
            let line = (message.body as? NSNumber)?.doubleValue
        else {
            return
        }
        windowController?.sourceLineDidChange(line)
    }
}
