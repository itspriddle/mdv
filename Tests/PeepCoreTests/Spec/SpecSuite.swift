import Foundation

@testable import MdvCore

/// The vendored spec fixtures (`Fixtures/spec`) and their documented exceptions.
enum SpecSuite {
    /// Spec files run by `SpecConformanceTests`, in order.
    static let files = ["spec.txt", "extensions.txt", "regression.txt"]

    /// Every example in every spec file, disabled ones included (they are skipped at run time).
    static func examples() throws -> [SpecExample] {
        try files.flatMap { file in
            try SpecParser.parse(fixture(file), file: file)
        }
    }

    /// `exceptions.json`: spec file name → example number (as a string) → reason.
    static func exceptions() throws -> [String: [String: String]] {
        let data = Data(try fixture("exceptions.json").utf8)
        return try JSONDecoder().decode([String: [String: String]].self, from: data)
    }

    /// The exception reason for an example, if it is listed.
    static func exception(for example: SpecExample, in exceptions: [String: [String: String]]) -> String? {
        exceptions[example.file]?[String(example.number)]
    }

    /// Spec-mode options for an example. `extensions.txt` runs with every extension, like
    /// cmark-gfm's own suite; the other files enable only the extensions an example's fence names.
    static func options(for example: SpecExample) -> RenderOptions {
        var options = RenderOptions.spec
        if example.file != "extensions.txt" {
            options.flavor.extensions = Set(example.tags.compactMap { extensionsByTag[$0] })
        }
        return options
    }

    /// cmark's extension names (as used in example fences) mapped to mdv's. `tagfilter` has no
    /// counterpart: mdv's sanitizer (#7) replaces it, so tagfilter examples are permanent
    /// exceptions.
    private static let extensionsByTag: [String: MarkdownExtension] = [
        "table": .table,
        "strikethrough": .strikethrough,
        "autolink": .autolink,
        "tasklist": .taskList,
        "footnotes": .footnotes,
    ]

    private static func fixture(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/spec")
        else {
            throw SpecFileError.missing(name)
        }
        let data = try Data(contentsOf: url)
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw SpecFileError.notUTF8(name)
        }
        return text
    }
}
