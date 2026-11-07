import Foundation
import Synchronization
import Yams

/// Parses YAML frontmatter with Yams, defensively. Frontmatter is untrusted, so parsing is bounded:
///
/// - **Size:** blocks over `maximumSize` bytes are not parsed.
/// - **Aliases:** Yams expands aliases while composing and hashes every mapping key, so an
///   "alias bomb" (`&a [x, x]`, `&b [*a, *a]`, …) costs exponential time inside Yams itself, before
///   any of our limits could run. A lexical pre-scan counts alias references and refuses the block
///   when there are more than `maximumAliases`; it errs on the side of counting too many.
/// - **Stack:** Yams composes recursively (libyaml caps nesting at 1000 levels), which overflows
///   the 512 KB stack of a secondary or Swift concurrency thread. Parsing runs on a dedicated thread
///   with a `parserStackSize` stack, and Yams nodes are freed there too.
/// - **Result size:** converting to `FrontmatterValue` stops past `maximumValues` values,
///   `maximumScalarBytes` of scalar text, or `maximumDepth` levels of nesting.
///
/// Every failure leaves the block hidden and sets `Frontmatter.error`; rendering never fails.
enum YAMLFrontmatter {
    static let maximumSize = 64 * 1024
    static let maximumAliases = 8
    static let maximumValues = 10_000
    static let maximumScalarBytes = 1024 * 1024
    static let maximumDepth = 32
    static let parserStackSize = 8 * 1024 * 1024

    static func parse(_ raw: String, lineCount: Int) -> Frontmatter {
        var frontmatter = Frontmatter(format: .yaml, raw: raw, lineCount: lineCount)
        switch load(raw) {
        case .success(let entries):
            frontmatter.entries = entries
        case .failure(let error):
            frontmatter.error = error.message
        }
        return frontmatter
    }

    static func load(_ yaml: String) -> Result<[FrontmatterEntry], LoadError> {
        guard yaml.utf8.count <= maximumSize else {
            return .failure(LoadError("Frontmatter is larger than \(maximumSize / 1024) KB and was not parsed."))
        }
        guard aliasCount(in: yaml) <= maximumAliases else {
            return .failure(LoadError("Frontmatter uses more than \(maximumAliases) YAML aliases and was not parsed."))
        }
        return onLargeStack { compose(yaml) }
    }

    struct LoadError: Error, Equatable {
        let message: String

        init(_ message: String) {
            self.message = message
        }
    }

    // MARK: - Composing

    private static func compose(_ yaml: String) -> Result<[FrontmatterEntry], LoadError> {
        let root: Node?
        do {
            root = try Yams.compose(yaml: yaml)
        } catch {
            return .failure(LoadError("Invalid YAML frontmatter: \(error)"))
        }
        guard let root, root.null == nil else {
            return .success([])
        }
        guard let mapping = root.mapping else {
            return .failure(LoadError("YAML frontmatter must be a mapping of keys to values."))
        }
        var converter = Converter()
        do {
            return .success(try converter.entries(of: mapping, depth: 1))
        } catch {
            return .failure(error)
        }
    }

    /// Converts Yams nodes into `FrontmatterValue`s within the result-size limits.
    private struct Converter {
        private var valueCount = 0
        private var scalarBytes = 0

        mutating func entries(of mapping: Node.Mapping, depth: Int) throws(LoadError) -> [FrontmatterEntry] {
            var entries: [FrontmatterEntry] = []
            for (key, value) in mapping {
                guard let keyText = key.scalar?.string else {
                    throw LoadError("YAML frontmatter keys must be plain values.")
                }
                try count(scalar: keyText)
                entries.append(FrontmatterEntry(key: keyText, value: try convert(value, depth: depth)))
            }
            return entries
        }

        private mutating func convert(_ node: Node, depth: Int) throws(LoadError) -> FrontmatterValue {
            guard depth < YAMLFrontmatter.maximumDepth else {
                throw LoadError("YAML frontmatter is nested more than \(YAMLFrontmatter.maximumDepth) levels deep.")
            }
            switch node {
            case .scalar(let scalar):
                if node.null != nil {
                    try count(scalar: "")
                    return .null
                }
                try count(scalar: scalar.string)
                return .scalar(scalar.string)
            case .sequence(let sequence):
                try count(scalar: "")
                var items: [FrontmatterValue] = []
                for item in sequence {
                    items.append(try convert(item, depth: depth + 1))
                }
                return .array(items)
            case .mapping(let mapping):
                try count(scalar: "")
                return .table(try entries(of: mapping, depth: depth + 1))
            case .alias:
                // Yams resolves aliases while composing; an unresolved one is unexpected.
                throw LoadError("YAML frontmatter contains an unresolved alias.")
            }
        }

        private mutating func count(scalar text: String) throws(LoadError) {
            valueCount += 1
            scalarBytes += text.utf8.count
            guard valueCount <= YAMLFrontmatter.maximumValues, scalarBytes <= YAMLFrontmatter.maximumScalarBytes
            else {
                throw LoadError("YAML frontmatter is too large once aliases are expanded.")
            }
        }
    }

    /// Runs `body` on a new thread with a `parserStackSize` stack and waits for it. The thread runs
    /// at the caller's quality of service: a user-initiated render (or the main thread) waiting on
    /// a default-QoS thread is a priority inversion (the Thread Performance Checker flagged it
    /// under the M3 sanitizer pass, #45).
    private static func onLargeStack(
        _ body: @escaping @Sendable () -> Result<[FrontmatterEntry], LoadError>
    ) -> Result<[FrontmatterEntry], LoadError> {
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            let value = body()
            box.result.withLock { $0 = value }
            done.signal()
        }
        thread.stackSize = parserStackSize
        thread.qualityOfService = Thread.current.qualityOfService
        thread.start()
        done.wait()
        return box.result.withLock { $0 } ?? .failure(LoadError("YAML frontmatter could not be parsed."))
    }

    private final class ResultBox: Sendable {
        let result = Mutex<Result<[FrontmatterEntry], LoadError>?>(nil)
    }

    // MARK: - Alias pre-scan

    /// Counts alias references (`*name` where a YAML node can start) outside quoted strings, block
    /// scalars, and comments. Only an upper bound is needed: it may count a `*` that YAML would read
    /// as text (e.g. a plain scalar continued on a line starting with `*`), but never misses one.
    static func aliasCount(in yaml: String) -> Int {
        var scanner = AliasScanner()
        var line: [UInt8] = []
        for byte in yaml.utf8 {
            if byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") {
                scanner.scan(line: line)
                line.removeAll(keepingCapacity: true)
            } else {
                line.append(byte)
            }
        }
        scanner.scan(line: line)
        return scanner.aliases
    }
}

/// Line-by-line YAML lexer state for `YAMLFrontmatter.aliasCount(in:)`.
private struct AliasScanner {
    private enum Quote {
        case none
        case single
        case double
    }

    private(set) var aliases = 0
    private var quote = Quote.none
    private var flowDepth = 0
    /// Indentation of the line that opened a block scalar (`|` or `>`); more-indented and blank
    /// lines after it are the scalar's text.
    private var blockScalarIndent: Int?

    // The line being scanned.
    private var line: [UInt8] = []
    private var index = 0
    private var indent = 0
    /// The next non-blank character starts a node (so `*` there is an alias).
    private var nodeStart = false

    mutating func scan(line newLine: [UInt8]) {
        line = newLine
        index = 0
        indent = line.prefix { $0 == UInt8(ascii: " ") }.count
        if let blockIndent = blockScalarIndent {
            if indent > blockIndent || line.allSatisfy(Self.isBlank) {
                return
            }
            blockScalarIndent = nil
        }

        nodeStart = quote == .none
        while index < line.count {
            let byte = line[index]
            let following: UInt8? = index + 1 < line.count ? line[index + 1] : nil
            index += 1

            if quote != .none {
                scanQuoted(byte, following: following)
            } else if Self.isBlank(byte) {
                continue
            } else if byte == UInt8(ascii: "#"), index == 1 || Self.isBlank(line[index - 2]) {
                return  // A comment.
            } else if nodeStart {
                scanNodeStart(byte, following: following)
                if blockScalarIndent != nil {
                    return  // The rest of the line is block scalar indicators or a comment.
                }
            } else {
                scanStructure(byte, following: following)
            }
        }
    }

    private mutating func scanQuoted(_ byte: UInt8, following: UInt8?) {
        switch quote {
        case .double:
            if byte == UInt8(ascii: "\\") {
                index += 1
            } else if byte == UInt8(ascii: "\"") {
                quote = .none
            }
        case .single:
            if byte == UInt8(ascii: "'") {
                if following == UInt8(ascii: "'") {
                    index += 1
                } else {
                    quote = .none
                }
            }
        case .none:
            break
        }
    }

    /// Handles the first character of a node (or an indicator before one).
    private mutating func scanNodeStart(_ byte: UInt8, following: UInt8?) {
        switch byte {
        case UInt8(ascii: "*"):
            aliases += 1
            nodeStart = false
        case UInt8(ascii: "\""):
            quote = .double
            nodeStart = false
        case UInt8(ascii: "'"):
            quote = .single
            nodeStart = false
        case UInt8(ascii: "|"), UInt8(ascii: ">"):
            if flowDepth == 0 {
                blockScalarIndent = indent
            } else {
                nodeStart = false
            }
        case UInt8(ascii: "&"), UInt8(ascii: "!"):
            // A node property; the node itself follows it.
            while index < line.count, !Self.isBlank(line[index]) {
                index += 1
            }
        case UInt8(ascii: "-"), UInt8(ascii: "?"):
            // Block indicators only when followed by a blank; otherwise a plain scalar starts.
            nodeStart = following.map(Self.isBlank) ?? true
        case UInt8(ascii: "["), UInt8(ascii: "{"):
            flowDepth += 1
        default:
            nodeStart = false
            scanStructure(byte, following: following)
        }
    }

    /// Indicators that end a node and allow another to start.
    private mutating func scanStructure(_ byte: UInt8, following: UInt8?) {
        switch byte {
        case UInt8(ascii: ":"):
            if following.map({ Self.isBlank($0) || (flowDepth > 0 && Self.isFlowIndicator($0)) }) ?? true {
                nodeStart = true
            }
        case UInt8(ascii: ","):
            if flowDepth > 0 {
                nodeStart = true
            }
        case UInt8(ascii: "["), UInt8(ascii: "{"):
            if flowDepth > 0 {
                flowDepth += 1
                nodeStart = true
            }
        case UInt8(ascii: "]"), UInt8(ascii: "}"):
            flowDepth = max(0, flowDepth - 1)
        default:
            break
        }
    }

    private static func isBlank(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
    }

    private static func isFlowIndicator(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: ",") || byte == UInt8(ascii: "[") || byte == UInt8(ascii: "]")
            || byte == UInt8(ascii: "{") || byte == UInt8(ascii: "}")
    }
}
