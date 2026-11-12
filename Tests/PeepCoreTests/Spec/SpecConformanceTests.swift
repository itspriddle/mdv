import Foundation
import Testing

@testable import PeepCore

/// Runs every CommonMark/GFM spec example (`Fixtures/spec`) through `HTMLRenderer` in spec mode
/// and compares normalized HTML. Examples listed in `Fixtures/spec/exceptions.json` are expected
/// to fail; if one starts passing, the test fails so the stale entry gets removed.
@Suite("Spec conformance")
struct SpecConformanceTests {
    private static let exceptions = Result { try SpecSuite.exceptions() }

    @Test("spec example", arguments: try SpecSuite.examples().filter { !$0.isDisabled })
    func example(_ example: SpecExample) throws {
        let exception = SpecSuite.exception(for: example, in: try Self.exceptions.get())
        let rendered = HTMLRenderer(options: SpecSuite.options(for: example)).render(example.markdown).html
        // Like cmark's spec_tests.py: CR LF counts as LF, and `<IGNORE>` accepts any output.
        let actual = rendered.replacingOccurrences(of: "\r\n", with: "\n")
        let expected = example.html.replacingOccurrences(of: "\r\n", with: "\n")
        let passed =
            expected.trimmingCharacters(in: .whitespacesAndNewlines) == "<IGNORE>"
            || HTMLNormalizer.normalize(actual) == HTMLNormalizer.normalize(expected)

        switch (passed, exception) {
        case (true, nil):
            break
        case (true, let reason?):
            Issue.record(
                "\(example.testDescription) now passes but is listed in exceptions.json (\(reason)); remove the entry")
        case (false, nil):
            Issue.record(Comment(rawValue: failureReport(example, actual: actual)))
        case (false, let reason?):
            withKnownIssue(Comment(rawValue: reason)) {
                Issue.record(Comment(rawValue: failureReport(example, actual: actual)))
            }
        }
    }

    @Test("exceptions.json lists only real, enabled examples with a pending or permanent reason")
    func exceptionsAreWellFormed() throws {
        let examples = try SpecSuite.examples()
        let exceptions = try Self.exceptions.get()
        #expect(Set(exceptions.keys).isSubset(of: SpecSuite.files))
        for (file, entries) in exceptions {
            for (number, reason) in entries {
                let example = examples.first { $0.file == file && String($0.number) == number }
                #expect(example != nil, "\(file) has no example #\(number)")
                #expect(example?.isDisabled != true, "\(file) #\(number) is disabled; it never runs")
                #expect(
                    reason.wholeMatch(of: /(pending #\d+(, #\d+)*|permanent): .+/) != nil,
                    "\(file) #\(number): reason must be `pending #N[, #M]: ...` or `permanent: ...`")
            }
        }
    }

    @Test("every spec file yields examples")
    func fixturesParse() throws {
        let counts = Dictionary(grouping: try SpecSuite.examples(), by: \.file).mapValues(\.count)
        #expect(counts == ["spec.txt": 672, "extensions.txt": 30, "regression.txt": 26])
    }

    /// The example's location and input, and a line diff of expected vs actual HTML.
    private func failureReport(_ example: SpecExample, actual: String) -> String {
        """
        \(example.testDescription), \(example.file):\(example.line)
        --- markdown
        \(example.markdown)--- expected (-) vs actual (+)
        \(lineDiff(expected: example.html, actual: actual))
        """
    }
}

/// A minimal unified-style line diff (no hunks; the inputs are short).
private func lineDiff(expected: String, actual: String) -> String {
    let old = expected.components(separatedBy: "\n")
    let new = actual.components(separatedBy: "\n")
    let difference = new.difference(from: old)
    var removed = Set<Int>()
    var inserted = Set<Int>()
    for change in difference {
        switch change {
        case .remove(let offset, _, _): removed.insert(offset)
        case .insert(let offset, _, _): inserted.insert(offset)
        }
    }
    var lines: [String] = []
    var oldIndex = 0
    var newIndex = 0
    while oldIndex < old.count || newIndex < new.count {
        if oldIndex < old.count, removed.contains(oldIndex) {
            lines.append("-" + old[oldIndex])
            oldIndex += 1
        } else if newIndex < new.count, inserted.contains(newIndex) {
            lines.append("+" + new[newIndex])
            newIndex += 1
        } else {
            lines.append(" " + (oldIndex < old.count ? old[oldIndex] : ""))
            oldIndex += 1
            newIndex += 1
        }
    }
    return lines.joined(separator: "\n")
}
