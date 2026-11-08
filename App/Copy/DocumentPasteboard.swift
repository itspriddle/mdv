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

    /// Writes an image for Copy Image: the file's own bytes under its type, and a PNG of it
    /// (drawn by the page) for apps that take only bitmaps, or for an SVG. A PNG file is
    /// written once, as is. No URL and no HTML, so no internal `mdv-doc` URL.
    static func writeImage(original: LocalImage?, png: Data?, to pasteboard: NSPasteboard) {
        var entries: [(type: NSPasteboard.PasteboardType, data: Data)] = []
        if let original, original.format == .png {
            entries.append((.png, original.data))
        } else {
            if let png {
                entries.append((.png, png))
            }
            if let original {
                entries.append((NSPasteboard.PasteboardType(original.format.typeIdentifier), original.data))
            }
        }
        pasteboard.clearContents()
        pasteboard.declareTypes(entries.map(\.type), owner: nil)
        for entry in entries {
            pasteboard.setData(entry.data, forType: entry.type)
        }
    }

    /// The rendered body fragment Copy as HTML copies: the default render options with the
    /// window's `flavor`, the same output as `mdv --html` without the page around it. No
    /// `data-source-line` annotations, and remote images are kept as written (the viewer's
    /// placeholders are display only; nothing is loaded by copying).
    nonisolated static func copyableHTML(for source: String, flavor: Flavor = .gfm) -> String {
        HTMLRenderer(options: RenderOptions(flavor: flavor)).render(source).html
    }
}
