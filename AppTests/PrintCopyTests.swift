import AppKit
import MdvCore
import PDFKit
import Testing
import WebKit

@testable import MdvApp

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
    func printToPDF() async throws {
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
        let window = try #require(controller.window)

        let pdf = folder.appending(path: "long.pdf")
        let operation = try document.printOperation(withSettings: [
            .jobDisposition: NSPrintInfo.JobDisposition.save, .jobSavingURL: pdf,
        ])
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        let done = await withCheckedContinuation { continuation in
            let delegate = PrintDelegate { continuation.resume(returning: $0) }
            operation.runModal(
                for: window, delegate: delegate,
                didRun: #selector(PrintDelegate.printOperationDidRun(_:success:context:)),
                contextInfo: Unmanaged.passRetained(delegate).toOpaque())
        }
        #expect(done)

        let pages = try #require(PDFDocument(url: pdf))
        #expect(pages.pageCount > 3, "paginated: \(pages.pageCount) pages")
        let text = (pages.string ?? "").filter { !$0.isWhitespace }
        #expect(text.contains(longLine), "the long code line wraps instead of being clipped")
        #expect(text.contains("column12value"), "the last table column prints")
        #expect(text.contains("Paragraph120ofthelongdocument."))
        #expect(text.contains("(https://example.com/printed-target)"), "external link targets are written out")
        #expect(!text.contains("#Section"), "no anchor icons")
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

/// Receives `NSPrintOperation.runModal`'s completion.
private final class PrintDelegate: NSObject {
    let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    @objc func printOperationDidRun(
        _ operation: NSPrintOperation, success: Bool, context: UnsafeMutableRawPointer?
    ) {
        if let context {
            Unmanaged<PrintDelegate>.fromOpaque(context).release()
        }
        completion(success)
    }
}
