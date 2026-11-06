import Foundation

/// The image formats the viewer serves from disk. A file is served only when its extension and
/// its content (`sniff(_:)`) name the same format.
public enum ImageFormat: String, Sendable, CaseIterable {
    case png
    case jpeg
    case gif
    case webp
    case svg

    /// The format a file extension names (case-insensitive), or nil.
    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "png": self = .png
        case "jpg", "jpeg": self = .jpeg
        case "gif": self = .gif
        case "webp": self = .webp
        case "svg": self = .svg
        default: return nil
        }
    }

    /// The `Content-Type` the file is served with.
    public var mimeType: String {
        switch self {
        case .png: "image/png"
        case .jpeg: "image/jpeg"
        case .gif: "image/gif"
        case .webp: "image/webp"
        case .svg: "image/svg+xml"
        }
    }

    /// How many leading bytes `sniff(_:)` looks at.
    public static let sniffLength = 4096

    /// The format `data` starts as, by magic number (raster formats) or by a root `<svg` element
    /// after an optional BOM, whitespace, XML declaration, comments, and doctype. Nil when it is
    /// none of them.
    public static func sniff(_ data: Data) -> ImageFormat? {
        let bytes = [UInt8](data.prefix(sniffLength))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return .png
        }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return .jpeg
        }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) {
            return .gif
        }
        if bytes.count >= 12, bytes.starts(with: Array("RIFF".utf8)), Array(bytes[8..<12]) == Array("WEBP".utf8) {
            return .webp
        }
        if isSVG(bytes) {
            return .svg
        }
        return nil
    }

    /// Whether the first element in `bytes` (UTF-8 text) is `<svg`. Skips what may legally
    /// precede the root element; anything else before it means "not SVG".
    private static func isSVG(_ bytes: [UInt8]) -> Bool {
        // Everything that matters here is ASCII. Drop a UTF-8 BOM and mask other non-ASCII
        // bytes (which may be a character cut off at `sniffLength`) as `?`.
        let body = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? Array(bytes.dropFirst(3)) : bytes
        guard let ascii = String(bytes: body.map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, encoding: .ascii) else {
            return false
        }
        var text = Substring(ascii)
        while true {
            text = text.drop { $0.isWhitespace }
            if text.hasPrefix("<?") {
                guard let end = text.range(of: "?>") else {
                    return false
                }
                text = text[end.upperBound...]
            } else if text.hasPrefix("<!--") {
                guard let end = text.range(of: "-->") else {
                    return false
                }
                text = text[end.upperBound...]
            } else if text.hasPrefix("<!") {
                // A doctype. An internal subset (`[...]`) would need real parsing; refuse it.
                guard let end = text.firstIndex(of: ">"), !text[..<end].contains("[") else {
                    return false
                }
                text = text[text.index(after: end)...]
            } else {
                break
            }
        }
        guard text.hasPrefix("<svg") else {
            return false
        }
        let next = text.dropFirst(4).first
        return next.map { $0.isWhitespace || $0 == ">" || $0 == "/" } ?? false
    }
}
