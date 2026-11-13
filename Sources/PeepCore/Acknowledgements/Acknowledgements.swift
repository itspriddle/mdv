import Foundation

/// The third-party notices Peep ships (#85): `Acknowledgements/Acknowledgements.json` lists each
/// bundled component and the file holding its license text, either in `Acknowledgements/` or a
/// vendored source's `Vendor/<name>/LICENSE`. Both folders are copied into the app's
/// resources, so `root` is the repository in tests and `Bundle.main.resourceURL` in the app,
/// and the same relative paths work in each.
public struct Acknowledgements: Sendable, Equatable {
    /// The manifest, relative to `root`.
    public static let manifestPath = "Acknowledgements/Acknowledgements.json"

    public let components: [Acknowledgement]

    public init(components: [Acknowledgement]) {
        self.components = components
    }

    /// Reads the manifest under `root`.
    public init(root: URL) throws {
        let data = try Data(contentsOf: root.appending(path: Self.manifestPath))
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        for component in manifest.components where !Self.isSafeRelativePath(component.licenseFile) {
            throw AcknowledgementsError.invalidLicensePath(component.licenseFile)
        }
        self.init(components: manifest.components)
    }

    /// The license text of `component`, read from under `root`.
    public static func licenseText(of component: Acknowledgement, root: URL) throws -> String {
        guard isSafeRelativePath(component.licenseFile) else {
            throw AcknowledgementsError.invalidLicensePath(component.licenseFile)
        }
        let data = try Data(contentsOf: root.appending(path: component.licenseFile))
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw AcknowledgementsError.unreadableLicense(component.licenseFile)
        }
        return text
    }

    /// `text` as paragraphs for a proportional font in a narrow view: blank lines separate
    /// paragraphs, a paragraph's hard-wrapped lines are joined with spaces, and a line that
    /// starts a list item (`*`, `-`, `1.`, `(a)`, `a.`) or is a rule (`=====`) keeps its own line.
    /// Only whitespace changes; every word of the license is kept, in order.
    public static func paragraphs(of text: String) -> [String] {
        var paragraphs: [String] = []
        var current: [String] = []
        var afterRule = false
        func finish() {
            if !current.isEmpty {
                paragraphs.append(current.joined())
                current = []
            }
        }
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let isRule = line.wholeMatch(of: /[=\-]+/) != nil
            if line.isEmpty {
                finish()
            } else if current.isEmpty {
                current.append(line)
            } else if isRule || afterRule || startsListItem(line) {
                current.append("\n" + line)
            } else {
                current.append(" " + line)
            }
            afterRule = isRule
        }
        finish()
        return paragraphs
    }

    private static func startsListItem(_ line: String) -> Bool {
        line.prefixMatch(of: /(?:[*•-]|\d+\.|\([a-z0-9]+\)|[a-z]\.)\s/) != nil
    }

    /// A relative path with no `..`, so a manifest entry can't name a file outside `root`.
    static func isSafeRelativePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && !path.hasPrefix("/") && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private struct Manifest: Decodable {
        let components: [Acknowledgement]
    }
}

/// One bundled third-party component and its notice.
public struct Acknowledgement: Sendable, Equatable, Decodable {
    public let name: String
    /// What Peep uses it for, in a few words.
    public let use: String
    public let homepage: String
    /// The license, as a short name (an SPDX identifier where there is one).
    public let license: String
    /// The license text's path, relative to the acknowledgements root.
    public let licenseFile: String
    /// Where the license text was copied from (not shown; for maintainers).
    public let licenseSource: String
    /// The `Vendor/` folder this entry covers, if any.
    public let vendor: String?
    /// The Swift package identity this entry covers, if any (lowercased, as in
    /// `Package.resolved`).
    public let package: String?

    public init(
        name: String, use: String, homepage: String, license: String, licenseFile: String,
        licenseSource: String, vendor: String? = nil, package: String? = nil
    ) {
        self.name = name
        self.use = use
        self.homepage = homepage
        self.license = license
        self.licenseFile = licenseFile
        self.licenseSource = licenseSource
        self.vendor = vendor
        self.package = package
    }
}

public enum AcknowledgementsError: Error, Equatable {
    /// A manifest entry's license path is absolute or leaves the root.
    case invalidLicensePath(String)
    /// A license file isn't UTF-8 text.
    case unreadableLicense(String)
}
