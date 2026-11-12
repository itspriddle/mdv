# Flavor fixtures

Run by `FlavorCorpusTests` (`make test-core`). Each folder is named for a registered flavor id
(`FlavorRegistry.bundled`); every `NAME.md` in it is rendered with that flavor and the otherwise
default `RenderOptions` (GitHub markup, heading anchors, highlighting, no source lines) and
compared byte for byte with the recorded `NAME.html`. Every registered flavor must have a folder
with at least one fixture, and every folder must be a registered flavor.

Re-record after an intended output change, and review the diff:

```sh
PEEP_RECORD_SNAPSHOTS=1 swift test --filter FlavorCorpusTests
```

- `commonmark/`: GFM syntax (tables, task lists, strikethrough, extended autolinks, footnotes,
  emoji shortcodes) must stay literal text; frontmatter is still detected.
- `gfm/`: the same inputs rendered as GFM. GFM is also checked against github.com's own
  rendering by the README corpus (`../corpus`, `GitHubCorpusTests`) and the reference fixtures
  (`../github`, `GitHubFixtureTests`), which render with the default flavor.

A feature that changes a flavor's output adds fixtures to that flavor's folder (and, for syntax
the other flavor leaves literal, to that folder too).

Wiki links (#53) are an opt-in built-in preprocessor, not flavor syntax, so their fixtures sit in
every flavor's folder: `wiki-links*.md` render with `.wikiLinks` on and a fake resolver over
`FlavorCorpusTests.wikiLinkPages` (no file system), and `wiki-links-off.md` renders with the
defaults to show the output is unchanged when they're off.
