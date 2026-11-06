import AppKit
import WebKit

/// Zoom (#26). View > Zoom In, Zoom Out, and Actual Size change the app-wide page zoom
/// (`ZoomSettings`, persisted), and every window follows it live. Pinch-to-zoom is the window's
/// own override: `WKWebView` magnification, which scales without reflowing, as in Safari. Window
/// restoration (#22) keeps a window's magnification; Actual Size clears it.
extension DocumentWindowController {
    /// The restorable-state key for the window's magnification (a `Double`, absent at 1).
    static let magnificationStateKey = "mdvMagnification"

    /// The magnification range pinch-to-zoom and restoration allow.
    nonisolated static let magnificationRange = 0.5...5.0

    /// Applies the app-wide level and follows its changes. Called once from `init`.
    func installZoom() {
        coordinator.webView.pageZoom = zoomSettings.level
        NotificationCenter.default.addObserver(
            self, selector: #selector(zoomSettingsDidChange(_:)), name: ZoomSettings.didChangeNotification,
            object: zoomSettings)
    }

    @objc private func zoomSettingsDidChange(_ notification: Notification) {
        coordinator.webView.pageZoom = zoomSettings.level
    }

    // MARK: Actions

    /// View > Zoom In (Command-+, and Command-=).
    @objc func zoomInDocument(_ sender: Any?) {
        if let level = PageZoom.larger(than: zoomSettings.level) {
            zoomSettings.level = level
        }
    }

    /// View > Zoom Out (Command-minus).
    @objc func zoomOutDocument(_ sender: Any?) {
        if let level = PageZoom.smaller(than: zoomSettings.level) {
            zoomSettings.level = level
        }
    }

    /// View > Actual Size (Command-0): the app-wide level back to 100%, and this window's
    /// pinch magnification cleared.
    @objc func resetDocumentZoom(_ sender: Any?) {
        zoomSettings.level = PageZoom.actualSize
        if coordinator.webView.magnification != 1 {
            coordinator.webView.magnification = 1
            window?.invalidateRestorableState()
        }
    }

    func validateZoomItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(zoomInDocument(_:)):
            PageZoom.larger(than: zoomSettings.level) != nil
        case #selector(zoomOutDocument(_:)):
            PageZoom.smaller(than: zoomSettings.level) != nil
        case #selector(resetDocumentZoom(_:)):
            !PageZoom.isActualSize(zoomSettings.level) || coordinator.webView.magnification != 1
        default:
            true
        }
    }

    // MARK: Restoration

    func encodeZoomState(with coder: NSCoder) {
        let magnification = coordinator.webView.magnification
        if magnification != 1 {
            coder.encode(Double(magnification), forKey: Self.magnificationStateKey)
        }
    }

    func restoreZoomState(with coder: NSCoder) {
        guard coder.containsValue(forKey: Self.magnificationStateKey),
            let magnification = Self.validMagnification(coder.decodeDouble(forKey: Self.magnificationStateKey))
        else {
            return
        }
        coordinator.webView.magnification = magnification
    }

    /// `value` if it is a usable magnification, else nil (restorable state is untrusted input).
    nonisolated static func validMagnification(_ value: Double) -> Double? {
        value.isFinite && magnificationRange.contains(value) ? value : nil
    }
}
