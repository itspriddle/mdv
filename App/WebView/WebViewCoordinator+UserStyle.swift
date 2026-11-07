import Foundation
import MdvCore

/// The reader's style controls (#37) on a loaded page: an in-place swap of the page's
/// `<style id="mdv-user">` text (`mdv.replaceStyle` in `DocumentBridge.js`), no reload, keeping
/// the reading position.
extension WebViewCoordinator {
    /// Writes the current `userStyle` into the loaded page, if any. Set `userStyle` first; it is
    /// read when the call runs, so overlapping calls end with the latest.
    func applyUserStyleToPage() async throws {
        guard hasLoadedPage else {
            return
        }
        let result = try await callBridge(
            "return mdv.replaceStyle(id, css);", arguments: ["id": ThemeLayer.user.name, "css": userStyle.layerCSS])
        guard (result as? NSNumber)?.boolValue == true else {
            throw BridgeError.unexpectedResult
        }
    }
}
