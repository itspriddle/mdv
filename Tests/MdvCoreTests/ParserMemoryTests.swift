// swift-format sorts imports case-sensitively, SwiftLint case-insensitively; they disagree here.
// swiftlint:disable sorted_imports
import Foundation
import Synchronization
import Testing
import cmark_gfm

@testable import MdvCore

// swiftlint:enable sorted_imports

/// Live and total allocations made through `countingAllocator`. Only `ParserMemoryTests` uses
/// it, and that suite is serialized.
private let liveAllocations = Atomic<Int>(0)
private let totalAllocations = Atomic<Int>(0)

private func countingAllocator() -> cmark_mem {
    cmark_mem(
        calloc: { count, size in
            let pointer = calloc(count, size)
            if pointer != nil {
                liveAllocations.add(1, ordering: .relaxed)
                totalAllocations.add(1, ordering: .relaxed)
            }
            return pointer
        },
        realloc: { old, size in
            let pointer = realloc(old, size)
            if old == nil, pointer != nil {
                liveAllocations.add(1, ordering: .relaxed)
                totalAllocations.add(1, ordering: .relaxed)
            }
            return pointer
        },
        free: { pointer in
            if pointer != nil {
                liveAllocations.subtract(1, ordering: .relaxed)
            }
            free(pointer)
        }
    )
}

/// About 5 MB of varied Markdown, exercising every node kind and all extensions.
private let largeDocument: String = {
    let chunk = """
        # Heading with *emphasis* and `code`

        A paragraph with **strong**, [a link](https://example.com "title"), ![image](a.png),
        an autolink <https://example.com>, www.example.com, ~~strike~~, &copy; entities,
        <span>inline html</span>, and a footnote[^note].\\
        Hard break above.

        > Quote with a list:
        > 1. one
        > 2. two

        - [x] task
        - [ ] task
          - nested

        | a | b |
        |:--|--:|
        | 1 | 2 |

        ```swift
        let x = "<code>"
        ```

            indented code

        <div>
        raw block
        </div>

        ***

        [^note]: The note.


        """
    let target = 5 * 1024 * 1024
    return String(repeating: chunk, count: target / chunk.utf8.count + 1)
}()

@Suite("MarkdownParser memory", .serialized)
struct ParserMemoryTests {
    @Test("parsing a 5 MB document frees every cmark allocation")
    func noLeaks() {
        #expect(largeDocument.utf8.count >= 5 * 1024 * 1024)
        var allocator = countingAllocator()
        let parser = MarkdownParser(extensions: Set(MarkdownExtension.allCases))
        let before = liveAllocations.load(ordering: .relaxed)
        let startTotal = totalAllocations.load(ordering: .relaxed)

        let tree = withUnsafeMutablePointer(to: &allocator) { parser.parse(largeDocument, allocator: $0) }

        #expect(totalAllocations.load(ordering: .relaxed) - startTotal > 100_000)
        #expect(liveAllocations.load(ordering: .relaxed) == before)
        #expect(tree.children.count > 1_000)
    }

    @Test("rendering a 5 MB document succeeds")
    func rendersLargeDocument() {
        let renderer = HTMLRenderer(options: RenderOptions(extensions: Set(MarkdownExtension.allCases)))
        let html = renderer.render(largeDocument).html
        #expect(html.utf8.count > largeDocument.utf8.count / 2)
        #expect(html.contains("<h1>Heading with <em>emphasis</em> and <code>code</code></h1>"))
    }
}
