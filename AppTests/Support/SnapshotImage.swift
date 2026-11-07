import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// An opaque sRGB bitmap for visual regression checks (#39): drawn from PDF pages, read from and
/// written to PNG, and compared with a tolerance for antialiasing.
struct SnapshotImage: Equatable {
    enum Failure: Error, CustomStringConvertible {
        case noColorSpace
        case noContext
        case unreadable(URL)
        case unwritable(URL)

        var description: String {
            switch self {
            case .noColorSpace: "no sRGB color space"
            case .noContext: "couldn't create a bitmap context"
            case .unreadable(let url): "couldn't read the PNG at \(url.path)"
            case .unwritable(let url): "couldn't write the PNG at \(url.path)"
            }
        }
    }

    let width: Int
    let height: Int
    /// RGBA, 8 bits per component, alpha always 255.
    let pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4, "RGBA pixel count")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// `pages` drawn top to bottom at `scale` pixels per point, on white, each page's media box
    /// at full width (pages narrower than the widest are left-aligned).
    @MainActor
    init(pages: [PDFPage], scale: CGFloat = 1) throws {
        let sizes = pages.map { page in
            let bounds = page.bounds(for: .mediaBox)
            return (width: Int((bounds.width * scale).rounded()), height: Int((bounds.height * scale).rounded()))
        }
        let width = sizes.map(\.width).max() ?? 0
        let height = sizes.map(\.height).reduce(0, +)
        var top = 0
        let pixels = try Self.draw(width: width, height: height) { context in
            for (page, size) in zip(pages, sizes) {
                context.saveGState()
                // Core Graphics' origin is bottom left: page n sits below pages 0..<n.
                context.translateBy(x: 0, y: CGFloat(height - top - size.height))
                context.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: context)
                context.restoreGState()
                top += size.height
            }
        }
        self.init(width: width, height: height, pixels: pixels)
    }

    /// The PNG at `url`, converted to sRGB.
    init(contentsOf url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw Failure.unreadable(url)
        }
        let pixels = try Self.draw(width: image.width, height: image.height) { context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        self.init(width: image.width, height: image.height, pixels: pixels)
    }

    /// Writes the image as an sRGB PNG without alpha, creating the folder.
    func writePNG(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw Failure.noColorSpace
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw Failure.unwritable(url)
        }
        // No PNG row filter: smaller than adaptive filtering for text on flat backgrounds.
        let options = [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGCompressionFilter: IMAGEIO_PNG_FILTER_NONE]]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.unwritable(url)
        }
    }

    /// An opaque sRGB RGBA bitmap filled white, then drawn by `body` (Core Graphics coordinates).
    private static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) throws -> [UInt8] {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw Failure.noColorSpace
        }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
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
            body(context)
            return true
        }
        guard drawn else {
            throw Failure.noContext
        }
        return buffer
    }
}

/// How an actual snapshot differs from its reference.
///
/// A pixel matches when every channel is within `tolerance` of the reference pixel, or, for
/// antialiasing and subpixel glyph placement, when it is within `tolerance` of some reference
/// pixel in the 3x3 neighborhood and the reference pixel is within `tolerance` of some actual
/// pixel in its neighborhood (both ways, so a thin line that disappears still counts). A real
/// change (a color, a border, a font, spacing that moves text) fails whole runs of pixels.
struct SnapshotDiff {
    /// Per-channel tolerance, 0...255.
    static let tolerance = 24

    let mismatchedPixels: Int
    let totalPixels: Int
    /// The reference faded to gray, with mismatched pixels in red.
    let image: SnapshotImage

    /// Nil when the sizes differ (a layout change: nothing to compare pixel by pixel).
    init?(actual: SnapshotImage, reference: SnapshotImage, tolerance: Int = Self.tolerance) {
        guard actual.width == reference.width, actual.height == reference.height else {
            return nil
        }
        let width = actual.width
        let height = actual.height
        var output = [UInt8](repeating: 255, count: width * height * 4)
        var mismatched = 0
        actual.pixels.withUnsafeBufferPointer { actualPixels in
            reference.pixels.withUnsafeBufferPointer { referencePixels in
                let images = Pair(
                    actual: actualPixels, reference: referencePixels, width: width, height: height,
                    tolerance: tolerance)
                for row in 0..<height {
                    for column in 0..<width {
                        let index = (row * width + column) * 4
                        if images.matches(column: column, row: row) {
                            // Faded reference: its luminance squeezed into 128...255.
                            let sum =
                                Int(referencePixels[index]) + Int(referencePixels[index + 1])
                                + Int(referencePixels[index + 2])
                            let value = UInt8(min(128 + sum / 6, 255))
                            output[index] = value
                            output[index + 1] = value
                            output[index + 2] = value
                        } else {
                            mismatched += 1
                            output[index] = 255
                            output[index + 1] = 0
                            output[index + 2] = 0
                        }
                    }
                }
            }
        }
        mismatchedPixels = mismatched
        totalPixels = width * height
        image = SnapshotImage(width: width, height: height, pixels: output)
    }

    /// The two images' pixels, compared one position at a time.
    private struct Pair {
        let actual: UnsafeBufferPointer<UInt8>
        let reference: UnsafeBufferPointer<UInt8>
        let width: Int
        let height: Int
        let tolerance: Int

        func matches(column: Int, row: Int) -> Bool {
            let index = (row * width + column) * 4
            if close(actual, index, reference, index) {
                return true
            }
            return hasNeighbor(in: reference, closeTo: actual, at: index, column: column, row: row)
                && hasNeighbor(in: actual, closeTo: reference, at: index, column: column, row: row)
        }

        /// Whether some pixel of `pixels` in the 3x3 neighborhood is close to `other`'s pixel.
        private func hasNeighbor(
            in pixels: UnsafeBufferPointer<UInt8>, closeTo other: UnsafeBufferPointer<UInt8>, at index: Int,
            column: Int, row: Int
        ) -> Bool {
            for neighborRow in max(row - 1, 0)...min(row + 1, height - 1) {
                for neighborColumn in max(column - 1, 0)...min(column + 1, width - 1)
                where close(other, index, pixels, (neighborRow * width + neighborColumn) * 4) {
                    return true
                }
            }
            return false
        }

        private func close(
            _ lhs: UnsafeBufferPointer<UInt8>, _ left: Int, _ rhs: UnsafeBufferPointer<UInt8>, _ right: Int
        ) -> Bool {
            abs(Int(lhs[left]) - Int(rhs[right])) <= tolerance
                && abs(Int(lhs[left + 1]) - Int(rhs[right + 1])) <= tolerance
                && abs(Int(lhs[left + 2]) - Int(rhs[right + 2])) <= tolerance
        }
    }
}
