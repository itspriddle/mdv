import AppKit
import PDFKit
import PeepCore
import Testing
import WebKit

@testable import PeepApp

/// Print, Copy Markdown Source / Copy as HTML, and the trimmed context menu (#26).
@MainActor
@Suite("Print and copy", .serialized, .timeLimit(.minutes(1)))
final class PrintCopyTests: DocumentWindowTestCase {
    // MARK: Copy

    @Test("Copy Markdown Source puts the whole source on the pasteboard as text and Markdown")
    func copySource() async throws {
        defer { closeAll() }
        let (_, controller) = try await open()
        controller.writeMarkdownSource(to: pasteboard)
        #expect(pasteboard.string(forType: .string) == Self.source)
        #expect(pasteboard.string(forType: DocumentPasteboard.markdownType) == Self.source)
        #expect(Set(pasteboard.types ?? []).isSuperset(of: [.string, DocumentPasteboard.markdownType]))
    }

    @Test("Copy as HTML puts the body fragment, without source lines, on the pasteboard as HTML and text")
    func copyHTML() async throws {
        defer { closeAll() }
        let (document, controller) = try await open()
        await controller.writeHTML(to: pasteboard)
        let html = try #require(pasteboard.string(forType: .html))
        #expect(pasteboard.string(forType: .string) == html)
        #expect(html == HTMLRenderer(options: RenderOptions()).render(Self.source).html)
        #expect(html.contains("<h1"))
        #expect(html.contains(#"<a href="https://example.com/page">link</a>"#))
        #expect(html.contains(#"src="https://example.com/a.png""#), "remote images are copied as written")
        #expect(!html.contains("data-source-line"))
        #expect(!html.contains("remote-image"), "no viewer placeholders")
        #expect(!html.contains("<html"), "a fragment, not the page")
        #expect(try #require(document.content).page.body.contains("data-source-line"), "the viewer's page has them")
    }

    @Test("Copy as HTML copies an alert as GitHub's markup, which pastes as its title and body (#52)")
    func copyAlert() throws {
        let html = DocumentPasteboard.copyableHTML(for: "> [!WARNING]\n> Mind the gap.\n")
        #expect(html.hasPrefix("<div class=\"markdown-alert markdown-alert-warning\">"))
        let pasted = try NSAttributedString(
            data: Data(html.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        ).string
        #expect(pasted.contains("Warning"))
        #expect(pasted.contains("Mind the gap."))
        #expect(!pasted.contains("[!WARNING]"))
    }

    @Test("copy items need a document with content")
    func copyValidation() throws {
        let controller = DocumentWindowController(zoomSettings: settings())
        let copySource = try #require(item("Copy Markdown Source", in: "Edit"))
        let copyHTML = try #require(item("Copy as HTML", in: "Edit"))
        #expect(!controller.validateMenuItem(copySource))
        #expect(!controller.validateMenuItem(copyHTML))
        controller.writeMarkdownSource(to: pasteboard)
        #expect(pasteboard.types?.isEmpty ?? true)
    }

    // MARK: Print

    @Test("the print operation prints the window's web view with a full print panel")
    func printOperation() async throws {
        defer { closeAll() }
        let (document, controller) = try await open(name: "Read Me.md")
        let operation = try document.printOperation(withSettings: [.copies: 2])
        #expect(operation.showsPrintPanel)
        #expect(operation.showsProgressPanel)
        #expect(operation.jobTitle == "Read Me")
        #expect(operation.view != nil)
        #expect(operation.view?.frame == controller.coordinator.webView.bounds)
        let options = operation.printPanel.options
        #expect(options.contains([.showsPaperSize, .showsOrientation, .showsScaling, .showsPreview]))
        let info = operation.printInfo
        #expect(info.horizontalPagination == .fit)
        #expect(info.verticalPagination == .automatic)
        #expect(!info.isVerticallyCentered)
        #expect(info.dictionary()[NSPrintInfo.AttributeKey.copies] as? Int == 2)
        #expect(document.printInfo.dictionary()[NSPrintInfo.AttributeKey.copies] as? Int != 2, "per job only")
    }

    @Test("printing needs a loaded page")
    func printWithoutPage() throws {
        let document = MarkdownDocument()
        #expect(throws: CocoaError.self) {
            try document.printOperation(withSettings: [:])
        }
    }

    /// Prints a long document to a PDF file with no panels (the jobDisposition `save` path that
    /// Save as PDF uses), then reads the PDF: it paginates, and nothing is clipped.
    @Test("a long document prints to paginated PDF with code and tables unclipped and no anchors")
    func printLongDocument() async throws {
        defer { closeAll() }
        let longLine = (1...40).map { "token\($0)" }.joined(separator: "_")
        let wideRow = "| " + (1...12).map { "column\($0)value" }.joined(separator: " | ") + " |"
        let header = "| " + (1...12).map { "h\($0)" }.joined(separator: " | ") + " |"
        let rule = "|" + String(repeating: " --- |", count: 12)
        let paragraphs = (1...120).map { "## Section \($0)\n\nParagraph \($0) of the long document." }
        let codeBlock = ["```", longLine, "```"].joined(separator: "\n")
        let table = [header, rule, wideRow].joined(separator: "\n")
        let link = "See [the site](https://example.com/printed-target)."
        let source = (["# Print Test", link, codeBlock, table] + paragraphs).joined(separator: "\n\n")
        let (document, controller) = try await open(source, name: "long.md")
        let pages = try await printToPDF(document, in: controller, named: "long.pdf")
        #expect(pages.pageCount > 3, "paginated: \(pages.pageCount) pages")
        let text = (pages.string ?? "").filter { !$0.isWhitespace }
        #expect(text.contains(longLine), "the long code line wraps instead of being clipped")
        #expect(text.contains("column12value"), "the last table column prints")
        #expect(text.contains("Paragraph120ofthelongdocument."))
        #expect(text.contains("(https://example.com/printed-target)"), "external link targets are written out")
        #expect(!text.contains("#Section"), "no anchor icons")
    }

    // MARK: Copy Link (#42)

    /// Opens the context menu's `contextmenu` event on the first element matching `selector`, as
    /// a right-click does, then runs Copy Link into the test pasteboard.
    func copyLink(onElementMatching selector: String, in controller: DocumentWindowController) async throws -> Bool {
        _ = try await controller.coordinator.webView.callAsyncJavaScript(
            """
            document.querySelector(selector).dispatchEvent(new MouseEvent("contextmenu", { bubbles: true }));
            return true;
            """, arguments: ["selector": selector], in: nil, contentWorld: AppScripts.world)
        return await controller.coordinator.copyContextMenuLink(to: pasteboard)
    }

    @Test("Copy Link copies a relative link as the file: URL it names, never peep-doc")
    func copyRelativeLink() async throws {
        defer { closeAll() }
        let source = "[guide](sub/my%20guide.md#set-up) [here](#title) [site](https://example.com/page?a=b)\n\nplain"
        let (_, controller) = try await open(source)

        #expect(try await copyLink(onElementMatching: "a[href^='sub/']", in: controller))
        let relative = try #require(pasteboard.string(forType: .string))
        #expect(relative.hasPrefix("file:///"), "\(relative)")
        #expect(relative.hasSuffix("/sub/my%20guide.md#set-up"), "\(relative)")
        let file = try #require(URL(string: relative))
        // The page is served at the folder's real path (`/private/var/...` for `/var/...`).
        #expect(file.path(percentEncoded: false).hasSuffix("/\(folder.lastPathComponent)/sub/my guide.md"))
        #expect(pasteboard.string(forType: .URL) == relative)
        #expect(!(pasteboard.types ?? []).contains(.fileURL), "a link, not a file to paste in Finder")

        #expect(try await copyLink(onElementMatching: "a[href='#title']", in: controller))
        let inPage = try #require(pasteboard.string(forType: .string))
        #expect(inPage.hasPrefix("file:///") && inPage.hasSuffix("/notes.md#title"), "\(inPage)")

        #expect(try await copyLink(onElementMatching: "a[href^='https:']", in: controller))
        #expect(pasteboard.string(forType: .string) == "https://example.com/page?a=b")

        for type in pasteboard.types ?? [] {
            #expect(pasteboard.string(forType: type)?.lowercased().contains("peep-doc") != true, "\(type.rawValue)")
        }
    }

    @Test("Copy Link outside a link copies nothing")
    func copyLinkWithoutLink() async throws {
        defer { closeAll() }
        let (_, controller) = try await open("[guide](guide.md)\n\nplain paragraph")
        pasteboard.clearContents()
        pasteboard.setString("unchanged", forType: .string)
        #expect(try await !copyLink(onElementMatching: "p:last-of-type", in: controller))
        #expect(pasteboard.string(forType: .string) == "unchanged")
    }

    @Test("the context menu's Copy Link runs the app's copy, or is removed")
    func copyLinkMenuItem() {
        func menu() -> NSMenu {
            let menu = NSMenu()
            let item = NSMenuItem(title: "Copy Link", action: Selector(("copyLink:")), keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier(WebViewContextMenu.copyLinkIdentifier)
            menu.addItem(item)
            menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
            return menu
        }
        var copied = 0
        let target = MenuItemTarget { copied += 1 }
        let redirected = menu()
        WebViewContextMenu.redirectCopyLink(in: redirected, to: target)
        let item = redirected.items[0]
        #expect(item.target === target)
        #expect(item.action == #selector(MenuItemTarget.performAction(_:)))
        NSApp.sendAction(#selector(MenuItemTarget.performAction(_:)), to: item.target, from: item)
        #expect(copied == 1)
        #expect(redirected.items[1].target == nil, "other items keep WebKit's action")

        let removed = menu()
        WebViewContextMenu.redirectCopyLink(in: removed, to: nil)
        #expect(removed.items.map(\.title) == ["Copy"])
    }

    // MARK: Context menu

    @Test("the context menu drops browser items the viewer can't perform")
    func contextMenu() {
        let menu = NSMenu()
        func add(_ identifier: String?, _ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
            menu.addItem(item)
        }
        add("WKMenuItemIdentifierOpenLink", "Open Link")
        add("WKMenuItemIdentifierOpenLinkInNewWindow", "Open Link in New Window")
        add("WKMenuItemIdentifierDownloadLinkedFile", "Download Linked File")
        add("WKMenuItemIdentifierCopyLink", "Copy Link")
        menu.addItem(.separator())
        add("WKMenuItemIdentifierReload", "Reload")
        menu.addItem(.separator())
        add("WKMenuItemIdentifierCopy", "Copy")
        add("WKMenuItemIdentifierLookUp", "Look Up")
        add(nil, "Services")
        menu.addItem(.separator())
        add("WKMenuItemIdentifierOpenImageInNewWindow", "Open Image in New Window")
        add("WKMenuItemIdentifierDownloadImage", "Download Image")

        WebViewContextMenu.trim(menu)
        #expect(
            menu.items.map { $0.isSeparatorItem ? "-" : $0.title } == [
                "Open Link", "Open Link in New Window", "Copy Link", "-", "Copy", "Look Up", "Services",
            ])
    }
}
