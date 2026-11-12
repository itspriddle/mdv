import Testing

@testable import PeepCore

/// The overrides `source`'s frontmatter declares.
private func overrides(_ source: String) -> DocumentOverrides {
    DocumentOverrides(frontmatter: Frontmatter.extract(from: source)?.frontmatter)
}

/// Frontmatter overrides (#54): parsing the `peep:` mapping and applying the flavor.
@Suite("Document overrides")
struct DocumentOverridesTests {
    // MARK: Parsing

    @Test("reads flavor, theme, and wikilinks from the Peep mapping")
    func parses() {
        let block = overrides("---\ntitle: T\npeep:\n  flavor: commonmark\n  theme: serif\n  wikilinks: true\n---\nx")
        #expect(block == DocumentOverrides(flavor: "commonmark", theme: "serif", wikiLinks: true))
        #expect(!block.isEmpty)
        let flow = overrides("---\npeep: { flavor: gfm, theme: \"custom:My Theme.css\", wikilinks: False }\n---\n")
        #expect(flow == DocumentOverrides(flavor: "gfm", theme: "custom:My Theme.css", wikiLinks: false))
    }

    @Test("no frontmatter, no Peep key, a null Peep, or malformed YAML give no overrides")
    func absent() {
        for source in [
            "# Just Markdown", "---\ntitle: T\n---\n", "---\npeep:\n---\n", "---\npeep: ~\n---\n",
            "---\npeep: [unclosed\n---\n", "---\npeep:\n  theme: ~\n---\n",
        ] {
            #expect(overrides(source) == .none, "\(source)")
        }
        #expect(DocumentOverrides(frontmatter: nil) == .none)
        #expect(DocumentOverrides.none.isEmpty)
    }

    @Test("bundled ids compare lowercased; custom theme ids keep their case")
    func normalization() {
        #expect(
            overrides("---\npeep: { flavor: \" CommonMark \", theme: GitHub }\n---\n")
                == DocumentOverrides(flavor: "commonmark", theme: "github"))
        #expect(overrides("---\npeep: { theme: custom:Dark.CSS }\n---\n").theme == "custom:Dark.CSS")
    }

    @Test("unknown keys and wrong types are ignored and reported, in document order")
    func ignored() {
        let source = """
            ---
            peep:
              theme: [serif]
              colour: red
              flavor: markdown
              wikilinks: yes
              Theme: serif
            ---
            """
        let result = overrides(source)
        #expect(result.isEmpty)
        #expect(
            result.ignored == [
                IgnoredOverride(key: "peep.theme", reason: .wrongType(expected: .string)),
                IgnoredOverride(key: "peep.colour", reason: .unknownKey),
                IgnoredOverride(key: "peep.flavor", reason: .unknownFlavor("markdown")),
                IgnoredOverride(key: "peep.wikilinks", reason: .wrongType(expected: .boolean)),
                IgnoredOverride(key: "peep.Theme", reason: .unknownKey),
            ])
        #expect(
            overrides("---\npeep: commonmark\n---\n").ignored == [
                IgnoredOverride(key: "peep", reason: .wrongType(expected: .mapping))
            ])
        #expect(overrides("---\npeep: [a]\n---\n").ignored.map(\.key) == ["peep"])
        #expect(
            overrides("---\npeep: { flavor: { id: gfm } }\n---\n").ignored == [
                IgnoredOverride(key: "peep.flavor", reason: .wrongType(expected: .string))
            ])
    }

    @Test("a valid key beside ignored ones still applies; duplicate keys are malformed YAML")
    func partial() {
        let result = overrides("---\npeep:\n  bogus: 1\n  theme: serif\n---\n")
        #expect(result.theme == "serif")
        #expect(result.ignored == [IgnoredOverride(key: "peep.bogus", reason: .unknownKey)])
        #expect(overrides("---\npeep: { theme: a, theme: b }\n---\n") == .none)
    }

    @Test(
        "theme ids are bounded, free of control characters, and name a custom file",
        arguments: [
            ("serif", "serif"), ("custom:x.css", "custom:x.css"), ("custom:", nil),
            (String(repeating: "a", count: 257), nil), ("a\u{7}b", nil),
            ("custom:../../etc/passwd", "custom:../../etc/passwd"),
        ] as [(String, String?)])
    func themeIDs(_ text: String, _ expected: String?) {
        #expect(DocumentOverrides.themeID(text) == expected)
    }

    @Test("an invalid theme id is reported")
    func invalidTheme() {
        #expect(
            overrides("---\npeep: { theme: \"custom:\" }\n---\n").ignored == [
                IgnoredOverride(key: "peep.theme", reason: .invalidThemeID)
            ])
    }

    @Test("TOML frontmatter isn't read; a Peep table in it is reported")
    func toml() {
        for source in [
            "+++\n[peep]\ntheme = \"serif\"\n+++\n", "+++\npeep.theme = \"serif\"\n+++\n",
            "+++\npeep = { theme = \"serif\" }\n+++\n", "+++\n[ peep.extra ]\n+++\n",
        ] {
            #expect(
                overrides(source)
                    == DocumentOverrides(ignored: [IgnoredOverride(key: "peep", reason: .tomlFrontmatter)]),
                "\(source)")
        }
        #expect(overrides("+++\ntitle = \"Peep rocks\"\n[peepx]\n+++\n") == .none)
    }

    @Test("ignored entries explain themselves without repeating long untrusted text")
    func descriptions() {
        #expect(
            IgnoredOverride(key: "peep.sanitize", reason: .unknownKey).description
                == "peep.sanitize isn't a setting a document can change (only flavor, theme, wikilinks); ignored.")
        #expect(
            IgnoredOverride(key: "peep.flavor", reason: .unknownFlavor("md")).description
                == "peep.flavor \"md\" isn't a flavor (gfm, commonmark); ignored.")
        #expect(
            IgnoredOverride(key: "peep.theme", reason: .wrongType(expected: .string)).description
                == "peep.theme must be a string; ignored.")
        let long = IgnoredOverride(key: "peep." + String(repeating: "k", count: 500), reason: .unknownKey)
        #expect(long.description.count < 200)
    }

    // MARK: Rendering

    @Test("the frontmatter flavor applies before the body is parsed and beats the options' flavor")
    func flavorBeforeParsing() {
        let table = "| a | b |\n| - | - |\n| 1 | 2 |\n\n:smile: ~~gone~~\n"
        let gfm = HTMLRenderer().render("---\npeep: { flavor: commonmark }\n---\n" + table)
        #expect(!gfm.html.contains("<table"))
        #expect(!gfm.html.contains("<del>"))
        #expect(gfm.html.contains(":smile:"))
        #expect(gfm.overrides.flavor == "commonmark")

        let commonmark = HTMLRenderer(options: RenderOptions(flavor: .commonmark))
        let upgraded = commonmark.render("---\npeep:\n  flavor: gfm\n---\n" + table)
        #expect(upgraded.html.contains("<table"))
        #expect(upgraded.html.contains("😄"))
    }

    @Test("an unknown flavor falls back to the options' flavor, not the registry's default")
    func unknownFlavorKeepsOptions() {
        let renderer = HTMLRenderer(options: RenderOptions(flavor: .commonmark))
        let rendered = renderer.render("---\npeep: { flavor: spec }\n---\n| a |\n| - |\n| 1 |\n")
        #expect(!rendered.html.contains("<table"))
        #expect(rendered.overrides.ignored == [IgnoredOverride(key: "peep.flavor", reason: .unknownFlavor("spec"))])
    }

    @Test("source lines and the title are unaffected by an override")
    func sourceLines() {
        var options = RenderOptions()
        options.sourceLines = true
        let rendered = HTMLRenderer(options: options).render(
            "---\ntitle: Doc\npeep:\n  flavor: commonmark\n---\n# Head\n")
        #expect(rendered.html.contains("data-source-line=\"6\""))
        #expect(rendered.title == "Doc")
    }

    @Test("the theme is reported for the caller and doesn't change the HTML")
    func themeReported() {
        let plain = HTMLRenderer().render("---\ntitle: T\n---\n# Hi\n")
        let themed = HTMLRenderer().render("---\ntitle: T\npeep: { theme: serif }\n---\n# Hi\n")
        #expect(themed.overrides.theme == "serif")
        #expect(themed.html == plain.html)
    }

    @Test("turning overrides off (and spec mode) ignores the Peep mapping")
    func disabled() {
        var options = RenderOptions()
        options.appliesDocumentOverrides = false
        let rendered = HTMLRenderer(options: options).render("---\npeep: { flavor: commonmark }\n---\n~~x~~\n")
        #expect(rendered.html.contains("<del>"))
        #expect(rendered.overrides == .none)
        #expect(!RenderOptions.spec.appliesDocumentOverrides)
        #expect(RenderOptions.spec.applying(DocumentOverrides(flavor: "commonmark")) == .spec)
    }

    @Test("wikilinks turns wiki links on or off, beating the reader's setting")
    func wikiLinksApplied() {
        var options = RenderOptions()
        #expect(options.applying(DocumentOverrides(wikiLinks: true)).builtInPreprocessors == [.wikiLinks])
        #expect(options.applying(DocumentOverrides(wikiLinks: false)) == options)
        options.builtInPreprocessors = [.wikiLinks]
        #expect(options.applying(DocumentOverrides(wikiLinks: false)).builtInPreprocessors.isEmpty)
        #expect(options.applying(DocumentOverrides()) == options)
        #expect(HTMLRenderer().render("---\npeep: { wikilinks: true }\n---\nx").overrides.wikiLinks == true)
        #expect(
            HTMLRenderer().render("---\npeep: { wikilinks: true }\n---\n[[#Top]]").html
                == "<p><a class=\"wikilink\" href=\"#top\">#Top</a></p>\n")
        var enabled = RenderOptions()
        enabled.builtInPreprocessors = [.wikiLinks]
        #expect(
            HTMLRenderer(options: enabled).render("---\npeep: { wikilinks: false }\n---\n[[#Top]]").html
                == "<p>[[#Top]]</p>\n")
    }

    @Test("a pinned flavor survives peep.flavor; other overrides still apply")
    func pinnedFlavor() {
        var options = RenderOptions(flavor: .gfm)
        options.pinnedOverrides = [.flavor]
        let overrides = DocumentOverrides(flavor: "commonmark", wikiLinks: true)
        let applied = options.applying(overrides)
        #expect(applied.flavor == .gfm)
        #expect(applied.builtInPreprocessors == [.wikiLinks])

        let rendered = HTMLRenderer(options: options).render(
            "---\npeep: { flavor: commonmark, wikilinks: true }\n---\n~~x~~ [[#Top]]\n")
        #expect(rendered.html.contains("<del>x</del>"))
        #expect(rendered.html.contains("class=\"wikilink\""))
        #expect(rendered.flavor == .gfm)
        #expect(rendered.overrides.flavor == "commonmark")
    }

    @Test("a pinned wikilinks setting survives peep.wikilinks in both directions")
    func pinnedWikiLinks() {
        var options = RenderOptions()
        options.pinnedOverrides = [.wikiLinks]
        #expect(options.applying(DocumentOverrides(wikiLinks: true)).builtInPreprocessors.isEmpty)
        options.builtInPreprocessors = [.wikiLinks]
        #expect(options.applying(DocumentOverrides(wikiLinks: false)).builtInPreprocessors == [.wikiLinks])
    }

    @Test("unpinned, the document's flavor applies and the rendered document reports it")
    func reportsFlavor() {
        #expect(RenderOptions().pinnedOverrides.isEmpty)
        #expect(HTMLRenderer().render("# Hi\n").flavor == .gfm)
        #expect(HTMLRenderer(options: RenderOptions(flavor: .commonmark)).render("# Hi\n").flavor == .commonmark)
        #expect(HTMLRenderer().render("---\npeep: { flavor: commonmark }\n---\nx\n").flavor == .commonmark)
        #expect(HTMLRenderer().render("---\npeep: { flavor: nope }\n---\nx\n").flavor == .gfm)
    }
}
