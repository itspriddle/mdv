import AppKit
import WebKit

/// Zoom (#26, per window since #47). View > Zoom In, Zoom Out, and Actual Size change this
/// window's page zoom (`zoomLevel`, `WKWebView.pageZoom`, which reflows); a new window starts at
/// Settings' default (`ZoomSettings`). Pinch-to-zoom is `WKWebView` magnification on top of it,
/// which scales without reflowing, as in Safari. Window restoration (#22) keeps both; Actual
/// Size resets both.
extension DocumentWindowController {
    /// The restorable-state key for the window's magnification (a `Double`, absent at 1).
    static let magnificationStateKey = "mdvMagnification"

    /// The restorable-state key for the window's page zoom (a `Double`, always written; absent
    /// only in state saved before #47, which then keeps Settings' default).
    static let pageZoomStateKey = "mdvPageZoom"

    /// The magnification range pinch-to-zoom and restoration allow.
    nonisolated static let magnificationRange = 0.5...5.0

    /// Applies the window's level. Called once from `init`.
    func installZoom() {
        coordinator.webView.pageZoom = zoomLevel
    }

    /// Sets this window's page zoom. Other windows and the default for new windows don't change.
    /// An unusable level is ignored.
    func setZoomLevel(_ level: Double) {
        guard let level = PageZoom.valid(level), level != zoomLevel else {
            return
        }
        zoomLevel = level
        coordinator.webView.pageZoom = level
        window?.invalidateRestorableState()
    }

    // MARK: Actions

    /// View > Zoom In (Command-+, and Command-=).
    @objc func zoomInDocument(_ sender: Any?) {
        if let level = PageZoom.larger(than: zoomLevel) {
            setZoomLevel(level)
        }
    }

    /// View > Zoom Out (Command-minus).
    @objc func zoomOutDocument(_ sender: Any?) {
        if let level = PageZoom.smaller(than: zoomLevel) {
            setZoomLevel(level)
        }
    }

    /// View > Actual Size (Command-0): this window back to 100% (not Settings' default), and its
    /// pinch magnification cleared.
    @objc func resetDocumentZoom(_ sender: Any?) {
        setZoomLevel(PageZoom.actualSize)
        if coordinator.webView.magnification != 1 {
            coordinator.webView.magnification = 1
            window?.invalidateRestorableState()
        }
    }

    func validateZoomItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(zoomInDocument(_:)):
            PageZoom.larger(than: zoomLevel) != nil
        case #selector(zoomOutDocument(_:)):
            PageZoom.smaller(than: zoomLevel) != nil
        case #selector(resetDocumentZoom(_:)):
            !PageZoom.isActualSize(zoomLevel) || coordinator.webView.magnification != 1
        default:
            true
        }
    }

    // MARK: Restoration

    func encodeZoomState(with coder: NSCoder) {
        coder.encode(zoomLevel, forKey: Self.pageZoomStateKey)
        let magnification = coordinator.webView.magnification
        if magnification != 1 {
            coder.encode(Double(magnification), forKey: Self.magnificationStateKey)
        }
    }

    /// Restores the page zoom and magnification. Restorable state is untrusted input: a value
    /// out of range is ignored.
    func restoreZoomState(with coder: NSCoder) {
        if coder.containsValue(forKey: Self.pageZoomStateKey) {
            setZoomLevel(coder.decodeDouble(forKey: Self.pageZoomStateKey))
        }
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
