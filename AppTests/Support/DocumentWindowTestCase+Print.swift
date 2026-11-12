import AppKit
import PDFKit
import Testing

@testable import MdvApp

extension DocumentWindowTestCase {
    /// Prints `document` to a PDF file with no panels (the job disposition `save` path that
    /// Save as PDF uses) and returns the PDF. Real WebKit printing, as File > Print does it.
    func printToPDF(_ document: MarkdownDocument, in controller: DocumentWindowController, named name: String)
        async throws -> PDFDocument
    {
        let window = try #require(controller.window)
        let pdf = folder.appending(path: name)
        // As File > Print does (`MarkdownDocument.printDocument(_:)`).
        await document.prepareForPrinting()
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
        #expect(done, "the print operation succeeded")
        return try #require(PDFDocument(url: pdf))
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

/// A PDF page drawn into an sRGB bitmap on white paper, for reading colors back.
struct PrintedPage {
    let width: Int
    let height: Int
    private let pixels: [UInt8]

    @MainActor
    init(_ page: PDFPage, scale: CGFloat = 1) throws {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = buffer.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else {
                return false
            }
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            return true
        }
        #expect(drawn)
        self.width = width
        self.height = height
        pixels = buffer
    }

    /// The fraction of pixels for which `matches(red, green, blue)` holds (components 0...255).
    func fraction(where matches: (Int, Int, Int) -> Bool) -> Double {
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4)
        where matches(Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2])) {
            count += 1
        }
        return Double(count) / Double(width * height)
    }

    /// The mean relative luminance (0 black ... 1 white), unweighted sRGB average.
    var meanLightness: Double {
        var total = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total += Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])
        }
        return Double(total) / Double(width * height * 3 * 255)
    }
}

extension PrintedPage {
    /// The base names of the fonts a PDF page uses (subset prefixes such as `AAAAAB+` kept).
    static func fontNames(on page: PDFPage) -> [String] {
        guard let dictionary = page.pageRef?.dictionary else {
            return []
        }
        var resources: CGPDFDictionaryRef?
        var fonts: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
            CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts
        else {
            return []
        }
        final class Names {
            var values: [String] = []
        }
        let names = Names()
        CGPDFDictionaryApplyBlock(
            fonts,
            { _, object, context in
                var font: CGPDFDictionaryRef?
                var name: UnsafePointer<CChar>?
                if let context, CGPDFObjectGetValue(object, .dictionary, &font), let font,
                    CGPDFDictionaryGetName(font, "BaseFont", &name), let name
                {
                    Unmanaged<Names>.fromOpaque(context).takeUnretainedValue().values.append(String(cString: name))
                }
                return true
            }, Unmanaged.passUnretained(names).toOpaque())
        return names.values
    }

    /// The point size of the font at the first occurrence of `text` on `page`.
    static func pointSize(of text: String, on page: PDFPage) -> CGFloat? {
        guard let attributed = page.attributedString else {
            return nil
        }
        let range = (attributed.string as NSString).range(of: text)
        guard range.location != NSNotFound else {
            return nil
        }
        return (attributed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)?.pointSize
    }
}
