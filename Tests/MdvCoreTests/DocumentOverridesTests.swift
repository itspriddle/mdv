import Testing

@testable import MdvCore

/// The overrides `source`'s frontmatter declares.
private func overrides(_ source: String) -> DocumentOverrides {
    DocumentOverrides(frontmatter: Frontmatter.extract(from: source)?.frontmatter)
}

/// Frontmatter overrides (#54): parsing the `mdv:` mapping and applying the flavor.
@Suite("Document overrides")
struct DocumentOverridesTests {
    // MARK: Parsing

    @Test("reads flavor, theme, and wikilinks from the mdv mapping")
    func parses() {
        let block = overrides("---\ntitle: T\nmdv:\n  flavor: commonmark\n  theme: serif\n  wikilinks: true\n---\nx")
        #expect(block == DocumentOverrides(flavor: "commonmark", theme: "serif", wikiLinks: true))
        #expect(!block.isEmpty)
        let flow = overrides("---\nmdv: { flavor: gfm, theme: \"custom:My Theme.css\", wikilinks: False }\n---\n")
        #expect(flow == DocumentOverrides(flavor: "gfm", theme: "custom:My Theme.css", wikiLinks: false))
    }

    @Test("no frontmatter, no mdv key, a null mdv, or malformed YAML give no overrides")
    func absent() {
        for source in [
            "# Just Markdown", "---\ntitle: T\n---\n", "---\nmdv:\n---\n", "---\nmdv: ~\n---\n",
            "---\nmdv: [unclosed\n---\n", "---\nmdv:\n  theme: ~\n---\n",
        ] {
            #expect(overrides(source) == .none, "\(source)")
        }
        #expect(DocumentOverrides(frontmatter: nil) == .none)
        #expect(DocumentOverrides.none.isEmpty)
    }

    @Test("bundled ids compare lowercased; custom theme ids keep their case")
    func normalization() {
        #expect(
            overrides("---\nmdv: { flavor: \" CommonMark \", theme: GitHub }\n---\n")
                == DocumentOverrides(flavor: "commonmark", theme: "github"))
        #expect(overrides("---\nmdv: { theme: custom:Dark.CSS }\n---\n").theme == "custom:Dark.CSS")
    }

    @Test("unknown keys and wrong types are ignored and reported, in document order")
    func ignored() {
        let source = """
            ---
            mdv:
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
                IgnoredOverride(key: "mdv.theme", reason: .wrongType(expected: .string)),
                IgnoredOverride(key: "mdv.colour", reason: .unknownKey),
                IgnoredOverride(key: "mdv.flavor", reason: .unknownFlavor("markdown")),
                IgnoredOverride(key: "mdv.wikilinks", reason: .wrongType(expected: .boolean)),
                IgnoredOverride(key: "mdv.Theme", reason: .unknownKey),
            ])
        #expect(
            overrides("---\nmdv: commonmark\n---\n").ignored == [
                IgnoredOverride(key: "mdv", reason: .wrongType(expected: .mapping))
            ])
        #expect(overrides("---\nmdv: [a]\n---\n").ignored.map(\.key) == ["mdv"])
        #expect(
            overrides("---\nmdv: { flavor: { id: gfm } }\n---\n").ignored == [
                IgnoredOverride(key: "mdv.flavor", reason: .wrongType(expected: .string))
            ])
    }

    @Test("a valid key beside ignored ones still applies; duplicate keys are malformed YAML")
    func partial() {
        let result = overrides("---\nmdv:\n  bogus: 1\n  theme: serif\n---\n")
        #expect(result.theme == "serif")
        #expect(result.ignored == [IgnoredOverride(key: "mdv.bogus", reason: .unknownKey)])
        #expect(overrides("---\nmdv: { theme: a, theme: b }\n---\n") == .none)
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
            overrides("---\nmdv: { theme: \"custom:\" }\n---\n").ignored == [
                IgnoredOverride(key: "mdv.theme", reason: .invalidThemeID)
            ])
    }

    @Test("TOML frontmatter isn't read; an mdv table in it is reported")
    func toml() {
        for source in [
            "+++\n[mdv]\ntheme = \"serif\"\n+++\n", "+++\nmdv.theme = \"serif\"\n+++\n",
            "+++\nmdv = { theme = \"serif\" }\n+++\n", "+++\n[ mdv.extra ]\n+++\n",
        ] {
            #expect(
                overrides(source)
                    == DocumentOverrides(ignored: [IgnoredOverride(key: "mdv", reason: .tomlFrontmatter)]),
                "\(source)")
        }
        #expect(overrides("+++\ntitle = \"mdv rocks\"\n[mdvx]\n+++\n") == .none)
    }

    @Test("ignored entries explain themselves without repeating long untrusted text")
    func descriptions() {
        #expect(
            IgnoredOverride(key: "mdv.sanitize", reason: .unknownKey).description
                == "mdv.sanitize isn't a setting a document can change (only flavor, theme, wikilinks); ignored.")
        #expect(
            IgnoredOverride(key: "mdv.flavor", reason: .unknownFlavor("md")).description
                == "mdv.flavor \"md\" isn't a flavor (gfm, commonmark); ignored.")
        #expect(
            IgnoredOverride(key: "mdv.theme", reason: .wrongType(expected: .string)).description
                == "mdv.theme must be a string; ignored.")
        let long = IgnoredOverride(key: "mdv." + String(repeating: "k", count: 500), reason: .unknownKey)
        #expect(long.description.count < 200)
    }

    // MARK: Rendering

    @Test("the frontmatter flavor applies before the body is parsed and beats the options' flavor")
    func flavorBeforeParsing() {
        let table = "| a | b |\n| - | - |\n| 1 | 2 |\n\n:smile: ~~gone~~\n"
        let gfm = HTMLRenderer().render("---\nmdv: { flavor: commonmark }\n---\n" + table)
        #expect(!gfm.html.contains("<table"))
        #expect(!gfm.html.contains("<del>"))
        #expect(gfm.html.contains(":smile:"))
        #expect(gfm.overrides.flavor == "commonmark")

        let commonmark = HTMLRenderer(options: RenderOptions(flavor: .commonmark))
        let upgraded = commonmark.render("---\nmdv:\n  flavor: gfm\n---\n" + table)
        #expect(upgraded.html.contains("<table"))
        #expect(upgraded.html.contains("😄"))
    }

    @Test("an unknown flavor falls back to the options' flavor, not the registry's default")
    func unknownFlavorKeepsOptions() {
        let renderer = HTMLRenderer(options: RenderOptions(flavor: .commonmark))
        let rendered = renderer.render("---\nmdv: { flavor: spec }\n---\n| a |\n| - |\n| 1 |\n")
        #expect(!rendered.html.contains("<table"))
        #expect(rendered.overrides.ignored == [IgnoredOverride(key: "mdv.flavor", reason: .unknownFlavor("spec"))])
    }

    @Test("source lines and the title are unaffected by an override")
    func sourceLines() {
        var options = RenderOptions()
        options.sourceLines = true
        let rendered = HTMLRenderer(options: options).render(
            "---\ntitle: Doc\nmdv:\n  flavor: commonmark\n---\n# Head\n")
        #expect(rendered.html.contains("data-source-line=\"6\""))
        #expect(rendered.title == "Doc")
    }

    @Test("the theme is reported for the caller and doesn't change the HTML")
    func themeReported() {
        let plain = HTMLRenderer().render("---\ntitle: T\n---\n# Hi\n")
        let themed = HTMLRenderer().render("---\ntitle: T\nmdv: { theme: serif }\n---\n# Hi\n")
        #expect(themed.overrides.theme == "serif")
        #expect(themed.html == plain.html)
    }

    @Test("turning overrides off (and spec mode) ignores the mdv mapping")
    func disabled() {
        var options = RenderOptions()
        options.appliesDocumentOverrides = false
        let rendered = HTMLRenderer(options: options).render("---\nmdv: { flavor: commonmark }\n---\n~~x~~\n")
        #expect(rendered.html.contains("<del>"))
        #expect(rendered.overrides == .none)
        #expect(!RenderOptions.spec.appliesDocumentOverrides)
        #expect(RenderOptions.spec.applying(DocumentOverrides(flavor: "commonmark")) == .spec)
    }

    @Test("wikilinks is stored but changes nothing until wiki links exist (#53)")
    func wikiLinksStored() {
        let options = RenderOptions()
        #expect(options.applying(DocumentOverrides(wikiLinks: true)) == options)
        #expect(HTMLRenderer().render("---\nmdv: { wikilinks: true }\n---\nx").overrides.wikiLinks == true)
    }
}
