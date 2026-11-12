import Foundation

/// Takes the window's internal `mdv-doc` URLs out of pasteboard data that WebKit writes by
/// itself, such as a dragged link or image: each one becomes what Copy Link copies
/// (`CopyableLink`), the `file:` URL it names.
///
/// Entries are rewritten when they are a single URL (`public.url`, plain text) or a property
/// list of strings (WebKit's URL-and-title lists). Any other entry that mentions an `mdv-doc`
/// URL is dropped rather than guessed at, as is one whose `mdv-doc` URL names no file.
public enum PasteboardLinkRewriter {
    /// One pasteboard type and its data.
    public struct Entry: Equatable, Sendable {
        public var type: String
        public var data: Data

        public init(type: String, data: Data) {
            self.type = type
            self.data = data
        }
    }

    /// The entries to write in place of `entries` for the window `token`, in order; `nil` when
    /// none mentions an `mdv-doc` URL, so the pasteboard can be left alone.
    public static func rewrite(_ entries: [Entry], token: String) -> [Entry]? {
        guard entries.contains(where: { mentionsDocumentURL($0.data) }) else {
            return nil
        }
        return entries.compactMap { entry in
            guard mentionsDocumentURL(entry.data) else {
                return entry
            }
            return rewritten(entry.data, token: token).map { Entry(type: entry.type, data: $0) }
        }
    }

    /// `mdv-doc:` in ASCII (UTF-8), the scheme as WebKit serializes it.
    private static let marker = Data((DocumentURLScheme.name + ":").utf8)
    /// The same in UTF-16, either byte order, so text in that encoding isn't missed.
    private static let utf16Markers = [String.Encoding.utf16LittleEndian, .utf16BigEndian].compactMap {
        (DocumentURLScheme.name + ":").data(using: $0)
    }

    private static func mentionsDocumentURL(_ data: Data) -> Bool {
        let lowercased = Data(data.map { $0 >= 0x41 && $0 <= 0x5A ? $0 | 0x20 : $0 })
        return lowercased.range(of: marker) != nil || utf16Markers.contains { lowercased.range(of: $0) != nil }
    }

    /// `data` with its `mdv-doc` URLs replaced, or `nil` to drop it.
    private static func rewritten(_ data: Data, token: String) -> Data? {
        if isPropertyList(data) {
            var format = PropertyListSerialization.PropertyListFormat.binary
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: &format),
                let mapped = rewritten(plist: plist, token: token)
            else {
                return nil
            }
            return try? PropertyListSerialization.data(fromPropertyList: mapped, format: format, options: 0)
        }
        guard let string = String(bytes: data, encoding: .utf8), !string.utf8.contains(0) else {
            return nil
        }
        return rewritten(string: string, token: token).map { Data($0.utf8) }
    }

    /// Binary and XML property lists only: plain text parses as an OpenStep property list too.
    private static func isPropertyList(_ data: Data) -> Bool {
        let prefixes = ["bplist", "<?xml", "<plist", "<!DOCTYPE plist"].map { Data($0.utf8) }
        return prefixes.contains { data.starts(with: $0) }
    }

    private static func rewritten(plist: Any, token: String) -> Any? {
        switch plist {
        case let string as String:
            return rewritten(string: string, token: token)
        case let array as [Any]:
            let mapped = array.compactMap { rewritten(plist: $0, token: token) }
            return mapped.count == array.count ? mapped : nil
        case let dictionary as [String: Any]:
            var mapped: [String: Any] = [:]
            for (key, value) in dictionary {
                guard !mentionsDocumentURL(Data(key.utf8)), let value = rewritten(plist: value, token: token) else {
                    return nil
                }
                mapped[key] = value
            }
            return mapped
        default:
            // Numbers, dates, booleans; data is opaque, so it may not name an `mdv-doc` URL.
            if let data = plist as? Data {
                return mentionsDocumentURL(data) ? nil : data
            }
            return plist
        }
    }

    /// A string that is exactly an `mdv-doc` URL (surrounding whitespace aside) becomes the
    /// `file:` URL; other text that mentions one is dropped.
    private static func rewritten(string: String, token: String) -> String? {
        guard mentionsDocumentURL(Data(string.utf8)) else {
            return string
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == DocumentURLScheme.name,
            let link = CopyableLink.url(for: url, token: token)
        else {
            return nil
        }
        return link.absoluteString
    }
}
