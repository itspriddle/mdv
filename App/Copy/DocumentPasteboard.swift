import AppKit
import MdvCore

/// What Edit > Copy Markdown Source and Copy as HTML put on the pasteboard (#26).
@MainActor
enum DocumentPasteboard {
    /// The Markdown UTI, offered beside plain text so Markdown-aware apps can recognize it.
    static let markdownType = NSPasteboard.PasteboardType("net.daringfireball.markdown")

    /// Writes the whole file's source as plain text and as Markdown.
    static func writeMarkdownSource(_ source: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, markdownType], owner: nil)
        pasteboard.setString(source, forType: .string)
        pasteboard.setString(source, forType: markdownType)
    }

    /// Writes an HTML fragment as `text/html` (rich paste) and as plain text (its markup, for
    /// pasting into an editor).
    static func writeHTML(_ html: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.html, .string], owner: nil)
        pasteboard.setString(html, forType: .html)
        pasteboard.setString(html, forType: .string)
    }

    /// Writes a link for Copy Link (#42): its URL as a URL and as plain text. `url` must come
    /// from `CopyableLink` (never an internal `mdv-doc` URL). A `file:` URL is written as
    /// `public.url` text only, not as a file reference, so pasting it in Finder doesn't copy
    /// the file.
    static func writeLink(_ url: URL, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.URL, .string], owner: nil)
        pasteboard.setString(url.absoluteString, forType: .URL)
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    /// The rendered body fragment Copy as HTML copies: the default render options, the same
    /// output as `mdv --html` without the page around it. No `data-source-line` annotations, and
    /// remote images are kept as written (the viewer's placeholders are display only; nothing
    /// is loaded by copying).
    nonisolated static func copyableHTML(for source: String) -> String {
        HTMLRenderer(options: RenderOptions()).render(source).html
    }
}
