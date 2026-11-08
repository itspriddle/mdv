import AppKit

/// Edit > Copy Markdown Source and Copy as HTML (#26). Edit > Copy (the selection, as rich and
/// plain text) is the web view's own `copy:`.
extension DocumentWindowController {
    /// Edit > Copy Markdown Source: the whole file's source.
    @objc func copyMarkdownSource(_ sender: Any?) {
        writeMarkdownSource(to: .general)
    }

    /// Edit > Copy as HTML: the rendered body fragment. Rendered off the main thread, so the
    /// pasteboard is written shortly after the command.
    @objc func copyAsHTML(_ sender: Any?) {
        Task {
            await writeHTML(to: .general)
        }
    }

    func writeMarkdownSource(to pasteboard: NSPasteboard) {
        guard let source = markdownDocument?.content?.source else {
            return
        }
        DocumentPasteboard.writeMarkdownSource(source, to: pasteboard)
    }

    func writeHTML(to pasteboard: NSPasteboard) async {
        guard let content = markdownDocument?.content else {
            return
        }
        // What the window shows: the preferences its page was rendered with.
        let source = content.source
        let preferences = content.preferences
        let html = await Task.detached(priority: .userInitiated) {
            DocumentPasteboard.copyableHTML(for: source, preferences: preferences)
        }.value
        DocumentPasteboard.writeHTML(html, to: pasteboard)
    }

    func validateCopyItem(_ menuItem: NSMenuItem) -> Bool {
        markdownDocument?.content != nil
    }
}
