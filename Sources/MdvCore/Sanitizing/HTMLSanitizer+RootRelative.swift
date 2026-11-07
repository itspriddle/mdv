/// Root-relative URLs in raw HTML (`RenderOptions.linkRoot`): root-relative `a[href]`,
/// `img[src]`, and `source[srcset]` URLs are resolved against the root (`RootRelativeURL`) and
/// re-written percent-encoded, like Markdown URLs.
extension HTMLSanitizer {
    /// The sanitizer `HTMLRenderer` uses for `options` (`remoteImages`, `linkRoot`).
    init(for options: RenderOptions) {
        self.init(remoteImages: options.remoteImages, linkRoot: options.linkRoot)
    }

    func makeRawSanitizer() -> RawHTMLSanitizer {
        RawHTMLSanitizer(remoteImages: remoteImages, linkRoot: linkRoot)
    }
}

extension RawHTMLSanitizer {
    /// A fresh sanitizer with the same settings (nothing open, nothing dropped).
    func restarted() -> RawHTMLSanitizer {
        RawHTMLSanitizer(remoteImages: remoteImages, linkRoot: linkRoot)
    }

    /// URL attributes whose root-relative values resolve against `linkRoot`.
    private static let rootRelativeAttributes: [String: String] = ["a": "href", "img": "src", "source": "srcset"]

    /// The serialized value of a URL attribute with its root-relative URLs resolved
    /// (`RootRelativeURL`), or nil when nothing changes. Rewritten URLs are percent-encoded like
    /// Markdown URLs (`HTMLOutput.url`); everything else is escaped for a quoted attribute.
    func rootRelativeValue(of attribute: String, on element: String, _ value: AttributeValue) -> String? {
        let decoded = value.decoded
        guard let linkRoot, Self.rootRelativeAttributes[element] == attribute else {
            return nil
        }
        guard attribute == "srcset" else {
            return RootRelativeURL.resolve(decoded, root: linkRoot).map(Self.serializedURL)
        }
        var changed = false
        let pieces = SrcsetCandidates.split(decoded).map { piece in
            guard piece.isURL, let resolved = RootRelativeURL.resolve(piece.text, root: linkRoot) else {
                return HTMLDocument.escape(piece.text)
            }
            changed = true
            return Self.serializedURL(resolved)
        }
        return changed ? pieces.joined() : nil
    }

    private static func serializedURL(_ url: String) -> String {
        var output = HTMLOutput()
        output.url(url)
        return output.string
    }
}

/// Splits a `srcset` into its URLs and everything between them (whitespace, commas, and
/// descriptors), keeping every character, following the HTML "parse a srcset attribute"
/// steps: a URL is a run of non-whitespace (trailing commas end the candidate), and its
/// descriptors run to the next comma outside parentheses.
enum SrcsetCandidates {
    struct Piece: Equatable {
        var text: String
        var isURL: Bool
    }

    static func split(_ srcset: String) -> [Piece] {
        var pieces: [Piece] = []
        var rest = Substring(srcset)
        func take(while predicate: (Character) -> Bool, isURL: Bool = false) -> Substring {
            let taken = rest.prefix(while: predicate)
            rest = rest.dropFirst(taken.count)
            if !taken.isEmpty {
                pieces.append(Piece(text: String(taken), isURL: isURL))
            }
            return taken
        }
        while !rest.isEmpty {
            _ = take { $0.isWhitespace || $0 == "," }
            guard !rest.isEmpty else {
                break
            }
            var url = rest.prefix { !$0.isWhitespace }
            let endsCandidate = url.hasSuffix(",")
            while url.hasSuffix(",") {
                url = url.dropLast()
            }
            rest = rest.dropFirst(url.count)
            pieces.append(Piece(text: String(url), isURL: true))
            if endsCandidate {
                continue
            }
            var depth = 0
            _ = take { character in
                if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth = max(0, depth - 1)
                }
                return character != "," || depth > 0
            }
        }
        return pieces
    }
}
