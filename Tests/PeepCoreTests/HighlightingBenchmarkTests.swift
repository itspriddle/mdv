import Foundation
import Testing

@testable import MdvCore

/// Timings for the PR and for VISION's 200 ms open-to-display target. Opt-in, since timings are
/// noisy: `MDV_BENCHMARK=1 swift test --filter HighlightingBenchmark` (add `-c release` for
/// shipping numbers).
@Suite("Highlighting benchmark", .enabled(if: ProcessInfo.processInfo.environment["MDV_BENCHMARK"] != nil))
struct HighlightingBenchmarkTests {
    @Test("cold context and a typical README")
    func benchmark() throws {
        let url = try #require(
            Bundle.module.url(forResource: "readme", withExtension: "md", subdirectory: "Fixtures/highlighting"))
        let readme = try String(contentsOf: url, encoding: .utf8)
        let clock = ContinuousClock()

        let cold = HighlightJSHighlighter()
        let coldFirst = clock.measure { _ = cold.highlight("let x = 1", language: "swift") }
        let coldReadme = clock.measure { _ = HTMLRenderer(highlighter: HighlightJSHighlighter()).render(readme) }

        let warm = HTMLRenderer(highlighter: cold)
        let plain = HTMLRenderer(highlighter: nil)
        let warmReadme = Self.median { _ = warm.render(readme) }
        let plainReadme = Self.median { _ = plain.render(readme) }

        print(
            """
            [benchmark] cold context + first highlight: \(Self.ms(coldFirst))
            [benchmark] README, cold context (load + render): \(Self.ms(coldReadme))
            [benchmark] README, warm context (median of 20): \(Self.ms(warmReadme))
            [benchmark] README, no highlighting (median of 20): \(Self.ms(plainReadme))
            """)
        #expect(coldReadme < .milliseconds(200))
    }

    private static func median(_ body: () -> Void) -> Duration {
        let clock = ContinuousClock()
        let samples = (0..<20).map { _ in clock.measure(body) }.sorted()
        return samples[samples.count / 2]
    }

    private static func ms(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return String(format: "%.2f ms", Double(seconds) * 1000 + Double(attoseconds) / 1e15)
    }
}
