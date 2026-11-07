import AppKit
import WebKit

/// File > Print (#26): `NSDocument.printDocument(_:)` asks `MarkdownDocument` for a print
/// operation, which prints the window's web view. The print CSS is in MdvCore: structural
/// rules in `ThemeBase`, looks in the theme's `printStylesheet` (`@media print`). File > Page Setup is `NSDocument.runPageLayout(_:)`; its choices live in
/// the document's `printInfo`.
@MainActor
enum DocumentPrinting {
    /// The print info for one print job: the document's page setup plus `settings` (from
    /// `printDocument(withSettings:)`), with WebKit's own pagination laid out to the page width.
    static func printInfo(from base: NSPrintInfo, settings: [NSPrintInfo.AttributeKey: Any]) -> NSPrintInfo {
        let info = (base.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.dictionary().addEntries(from: settings)
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        return info
    }

    /// A print operation for the page in `webView`, with the print panel (preview, paper size,
    /// orientation, scale, and PDF / Save as PDF). `jobTitle` names the job and the PDF.
    static func operation(for webView: WKWebView, printInfo: NSPrintInfo, jobTitle: String) -> NSPrintOperation {
        let operation = webView.printOperation(with: printInfo)
        operation.jobTitle = jobTitle
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.printPanel.options.formUnion([.showsPaperSize, .showsOrientation, .showsScaling, .showsPreview])
        // WebKit's printing view has no size of its own; without one it can print blank pages.
        operation.view?.frame = webView.bounds
        return operation
    }
}

extension MarkdownDocument {
    /// Prints the page shown in this document's window.
    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws
        -> NSPrintOperation
    {
        guard
            let controller = windowControllers.lazy.compactMap({ $0 as? DocumentWindowController }).first,
            controller.coordinator.hasLoadedPage
        else {
            throw CocoaError(.featureUnsupported)
        }
        return DocumentPrinting.operation(
            for: controller.coordinator.webView,
            printInfo: DocumentPrinting.printInfo(from: printInfo, settings: printSettings),
            jobTitle: printJobTitle)
    }

    /// The file name without its extension (Save as PDF suggests `<title>.pdf`).
    var printJobTitle: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? displayName
    }
}
