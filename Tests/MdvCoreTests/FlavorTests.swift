import Testing

@testable import MdvCore

@Suite("Flavors")
struct FlavorTests {
    @Test("the bundled registry lists GFM (the default) and CommonMark")
    func bundled() {
        let registry = FlavorRegistry.bundled
        #expect(registry.defaultFlavor == .gfm)
        #expect(registry.flavors.map(\.id) == ["gfm", "commonmark"])
        #expect(registry.flavors.map(\.displayName) == ["GitHub Flavored Markdown", "CommonMark"])
        #expect(registry.contains(id: "commonmark"))
        #expect(!registry.contains(id: "spec"))
    }

    @Test(
        "ids resolve exactly; nil and unknown ids fall back to GFM",
        arguments: [
            ("gfm", "gfm"), ("commonmark", "commonmark"), ("CommonMark", "gfm"), ("", "gfm"), ("spec", "gfm"),
            ("markdown", "gfm"),
        ])
    func resolution(_ id: String, _ expected: String) {
        #expect(FlavorRegistry.bundled.flavor(id: id).id == expected)
    }

    @Test("a nil id is the default")
    func nilID() {
        #expect(FlavorRegistry.bundled.flavor(id: nil) == .gfm)
    }

    @Test("a duplicate id is dropped; the first one wins")
    func duplicates() {
        let impostor = Flavor(id: "gfm", displayName: "Impostor", extensions: [])
        let registry = FlavorRegistry(defaultFlavor: .gfm, others: [impostor, .commonmark])
        #expect(registry.flavors == [.gfm, .commonmark])
        #expect(registry.flavor(id: "gfm") == .gfm)
    }

    @Test("GFM has every extension, alerts, and emoji; CommonMark has none of them")
    func definitions() {
        #expect(Flavor.gfm.extensions == Set(MarkdownExtension.allCases))
        #expect(Flavor.gfm.transforms == [.alerts, .emojiShortcodes])
        #expect(Flavor.commonmark.extensions.isEmpty)
        #expect(Flavor.commonmark.transforms.isEmpty)
        #expect(Flavor.spec.extensions == Set(MarkdownExtension.allCases))
        #expect(Flavor.spec.transforms.isEmpty)
    }

    @Test("viewer features are independent of the flavor")
    func featuresIndependent() {
        var options = RenderOptions(flavor: .commonmark)
        options.sourceLines = true
        let html = HTMLRenderer(options: options).render("---\ntitle: T\n---\n# Head\n\n```swift\nlet x = 1\n```\n")
            .html
        #expect(html.contains("id=\"head\""))
        #expect(html.contains("data-source-line=\"4\""))
        #expect(html.contains("hljs-keyword"))
        #expect(HTMLRenderer(options: options).render("---\ntitle: T\n---\nx").title == "T")
        #expect(HTMLRenderer(options: options).render("<script>x</script>").html.isEmpty)
    }

    @Test("the default options are GFM with no built-in preprocessors")
    func defaults() {
        #expect(RenderOptions().flavor == .gfm)
        #expect(RenderOptions().builtInPreprocessors.isEmpty)
        #expect(RenderOptions.spec.flavor == .spec)
        #expect(RenderOptions.spec.transforms.isEmpty)
    }
}

@Suite("Markdown transforms")
struct MarkdownTransformTests {
    @Test("transforms run in declaration order, whoever enables them")
    func order() {
        #expect(MarkdownTransform.ordered(Set(MarkdownTransform.allCases)) == MarkdownTransform.allCases)
        var options = RenderOptions(flavor: .commonmark)
        #expect(options.transforms.isEmpty)
        options.builtInPreprocessors = [.emojiShortcodes]
        #expect(options.transforms == [.emojiShortcodes])
        options.flavor = .gfm
        #expect(options.transforms == [.alerts, .emojiShortcodes])
        options.builtInPreprocessors = [.emojiShortcodes, .wikiLinks]
        #expect(options.transforms == [.alerts, .wikiLinks, .emojiShortcodes])
    }

    @Test("a built-in preprocessor works in any flavor")
    func builtInPreprocessorInCommonMark() {
        var options = RenderOptions(flavor: .commonmark)
        options.builtInPreprocessors = [.emojiShortcodes]
        #expect(HTMLRenderer(options: options).render(":tada: | a |\n| - |").html == "<p>🎉 | a |\n| - |</p>\n")
    }

    @Test("transformed nodes keep the source range of the text they replace")
    func sourceRanges() {
        var options = RenderOptions()
        options.sourceLines = true
        #expect(
            HTMLRenderer(options: options).render("a\n\nb :tada:\n").html.contains("<p data-source-line=\"3\">b 🎉</p>"))
    }

    @Test("html(for:) runs the options' transforms")
    func htmlForNode() {
        let root = MarkdownNode(.paragraph, children: [MarkdownNode(.text(":tada:"))])
        #expect(HTMLRenderer().html(for: root) == "<p>🎉</p>\n")
        #expect(HTMLRenderer(options: RenderOptions(flavor: .commonmark)).html(for: root) == "<p>:tada:</p>\n")
    }
}

private struct PreprocessorFailure: Error {}

@Suite("Render pipeline")
struct RenderPipelineTests {
    struct Upcasing: SourcePreprocessor {
        func preprocess(_ source: String) async throws -> String { source.uppercased() }
    }

    struct AddingLines: SourcePreprocessor {
        func preprocess(_ source: String) async throws -> String { "added\n\n" + source }
    }

    struct Failing: SourcePreprocessor {
        func preprocess(_ source: String) async throws -> String { throw PreprocessorFailure() }
    }

    @Test("without a preprocessor, the async render equals render(_:)")
    func noPreprocessor() async throws {
        let renderer = HTMLRenderer()
        #expect(try await renderer.render("# A :tada:", preprocessor: nil) == renderer.render("# A :tada:"))
    }

    @Test("the preprocessor's output is what gets parsed, frontmatter included")
    func preprocessorFirst() async throws {
        let document = try await HTMLRenderer().render("---\ntitle: t\n---\n# a\n", preprocessor: Upcasing())
        #expect(document.frontmatter?.title == nil)
        #expect(document.frontmatter?.raw == "TITLE: T\n")
        #expect(document.headings.map(\.text) == ["A"])
    }

    @Test("source lines refer to the preprocessor's output")
    func sourceLinesAfterPreprocessor() async throws {
        var options = RenderOptions()
        options.sourceLines = true
        let document = try await HTMLRenderer(options: options).render("# Head\n", preprocessor: AddingLines())
        #expect(document.html.contains("<h1 id=\"head\" data-source-line=\"3\">"))
        #expect(document.headings.first?.sourceLine == 3)
    }

    @Test("a preprocessor's error is thrown to the caller")
    func failure() async {
        await #expect(throws: PreprocessorFailure.self) {
            try await HTMLRenderer().render("x", preprocessor: Failing())
        }
    }
}
