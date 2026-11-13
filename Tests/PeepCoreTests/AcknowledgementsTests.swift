import Foundation
import Testing
import Yams

@testable import PeepCore

/// Every bundled third-party component has a notice (#85): each `Vendor/` folder and each
/// package the app or CLI links has an `Acknowledgements/Acknowledgements.json` entry, so adding
/// a dependency without its license fails here.
@Suite("Acknowledgements")
struct AcknowledgementsTests {
    static let root = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(components: "..", "..").standardizedFileURL

    /// Package identities that are resolved but never linked into Peep.app or the `peep` CLI.
    /// Empty today: swift-cmark and Yams are in PeepCore, swift-argument-parser in the embedded
    /// CLI. A build-only or test-only package goes here, with the reason.
    static let notShipped: Set<String> = []

    static func acknowledgements() throws -> Acknowledgements {
        try Acknowledgements(root: root)
    }

    @Test("every Vendor/ folder has an entry")
    func vendored() throws {
        let folders = try FileManager.default.contentsOfDirectory(
            at: Self.root.appending(path: "Vendor"), includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        #expect(!folders.isEmpty)
        let covered = Set(try Self.acknowledgements().components.compactMap(\.vendor))
        for folder in folders {
            #expect(covered.contains(folder.lastPathComponent), "Vendor/\(folder.lastPathComponent) has no entry")
        }
    }

    @Test("every resolved Swift package has an entry")
    func resolvedPackages() throws {
        struct Pin: Decodable { let identity: String }
        struct Resolved: Decodable { let pins: [Pin] }
        let data = try Data(contentsOf: Self.root.appending(path: "Package.resolved"))
        let identities = try JSONDecoder().decode(Resolved.self, from: data).pins.map(\.identity)
        #expect(!identities.isEmpty)
        let covered = Set(try Self.acknowledgements().components.compactMap(\.package))
        for identity in identities where !Self.notShipped.contains(identity) {
            #expect(covered.contains(identity), "package \(identity) has no entry")
        }
    }

    @Test("every remote package in project.yml has an entry")
    func xcodePackages() throws {
        let yaml = try String(contentsOf: Self.root.appending(path: "project.yml"), encoding: .utf8)
        let project = try #require(try Yams.load(yaml: yaml) as? [String: Any])
        let packages = try #require(project["packages"] as? [String: Any])
        let covered = Set(try Self.acknowledgements().components.compactMap(\.package))
        for case (let name, let spec as [String: Any]) in packages {
            guard let url = spec["url"] as? String else { continue }  // local packages (`path:`)
            let identity = Self.identity(ofPackageURL: url)
            if Self.notShipped.contains(identity) { continue }
            #expect(covered.contains(identity), "project.yml package \(name) (\(identity)) has no entry")
        }
    }

    @Test("package identities follow SwiftPM's (last path component, no .git, lowercased)")
    func identities() {
        #expect(Self.identity(ofPackageURL: "https://github.com/sparkle-project/Sparkle") == "sparkle")
        #expect(Self.identity(ofPackageURL: "https://github.com/jpsim/Yams.git") == "yams")
    }

    static func identity(ofPackageURL url: String) -> String {
        var name = url.split(separator: "/").last.map(String.init) ?? url
        if name.hasSuffix(".git") {
            name.removeLast(4)
        }
        return name.lowercased()
    }

    @Test("every entry has a readable license and the details the credits show")
    func entries() throws {
        let components = try Self.acknowledgements().components
        #expect(Set(components.map(\.name)).count == components.count)
        for component in components {
            let text = try Acknowledgements.licenseText(of: component, root: Self.root)
            #expect(text.contains("Copyright") || text.contains("License"), "\(component.name)")
            #expect(component.homepage.hasPrefix("https://"), "\(component.name)")
            #expect(component.licenseSource.hasPrefix("https://"), "\(component.name)")
            #expect(!component.use.isEmpty && !component.license.isEmpty, "\(component.name)")
        }
    }

    @Test("reflowing a license keeps every word, in order")
    func reflowKeepsWords() throws {
        func words(_ text: String) -> [Substring] {
            text.split(whereSeparator: \.isWhitespace)
        }
        for component in try Self.acknowledgements().components {
            let text = try Acknowledgements.licenseText(of: component, root: Self.root)
            let reflowed = Acknowledgements.paragraphs(of: text).joined(separator: "\n\n")
            #expect(words(reflowed) == words(text), "\(component.name)")
        }
    }

    @Test("joins hard-wrapped lines, keeps list items and rules on their own lines")
    func paragraphs() {
        let text = """
            Copyright (c) 2026 Someone

            Redistribution and use are
              permitted provided that:

            * Redistributions keep
              this notice.
            * Binaries reproduce it.
            1. First
            (a) Sub item
            -----
            THE END
            """
        #expect(
            Acknowledgements.paragraphs(of: text) == [
                "Copyright (c) 2026 Someone",
                "Redistribution and use are permitted provided that:",
                "* Redistributions keep this notice.\n* Binaries reproduce it.\n1. First\n(a) Sub item\n-----\nTHE END",
            ])
    }

    @Test("rejects license paths outside the root")
    func unsafePaths() {
        for path in ["/etc/passwd", "../LICENSE", "Vendor/../../x", "a//b", "", "./a"] {
            #expect(!Acknowledgements.isSafeRelativePath(path), "\(path)")
        }
        #expect(Acknowledgements.isSafeRelativePath("Vendor/highlight.js/LICENSE"))
        let outside = Acknowledgement(
            name: "x", use: "x", homepage: "https://x", license: "MIT", licenseFile: "../x",
            licenseSource: "https://x")
        #expect(throws: AcknowledgementsError.invalidLicensePath("../x")) {
            try Acknowledgements.licenseText(of: outside, root: Self.root)
        }
    }
}
