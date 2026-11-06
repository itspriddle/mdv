# Spec fixtures

Run by `SpecConformanceTests` (`make test-core`).

## Source

Copied unmodified from [swiftlang/swift-cmark](https://github.com/swiftlang/swift-cmark) tag
`0.9.0` (commit `08ddb528923cc1a6527e02b7a1aee9e516ca749a`), the version pinned in
`Package.resolved`. When the swift-cmark pin changes, re-copy these files from the new tag's
`test/` directory and update this section.

| File             | Upstream path         | Contents                                         |
| ---------------- | --------------------- | ------------------------------------------------ |
| `spec.txt`       | `test/spec.txt`       | GitHub Flavored Markdown spec 0.29 (CommonMark + GFM extension examples) |
| `extensions.txt` | `test/extensions.txt` | cmark-gfm extension tests                        |
| `regression.txt` | `test/regression.txt` | cmark-gfm regression tests (includes footnotes)  |

`regression.txt` has CR bytes that some examples depend on; `.gitattributes` marks these files
`-text` so Git never rewrites line endings.

## License

`spec.txt` and `extensions.txt` are licensed under
[CC-BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) (see their front matter).
`spec.txt` is by John MacFarlane and GitHub; `extensions.txt` is by Yuki Izumi (GitHub).
`regression.txt` is part of cmark-gfm, distributed under its BSD-2-Clause license
(`COPYING` in swift-cmark, Copyright (c) 2014, John MacFarlane).

## Running examples

Examples run the way cmark-gfm's `test/spec_tests.py` runs them, through `HTMLRenderer` with
`RenderOptions.spec`:

- `spec.txt` and `regression.txt` enable only the extensions named on an example's fence
  (`example table footnotes`); `extensions.txt` enables all of them.
- `example disabled` fences are skipped but keep their number.
- `RenderOptions.spec` sets `gfmMarkup = .cmark`: task lists and footnotes are written with
  cmark's reference markup, so these examples still check parsing, nesting, and numbering. The
  default GitHub markup is checked against GitHub's own output in `../github`.
- Output and expected HTML are compared after normalization (`HTMLNormalizer`, a port of
  cmark's `normalize.py`).

## Exceptions

`exceptions.json` maps file → example number → reason. Reasons are either:

- `pending #N: ...` (or `pending #N, #M: ...`): the feature lands in that issue. The issue removes
  its entries once they pass.
- `permanent: ...`: mdv deliberately differs.

Excepted examples are reported as known issues. If one starts passing, the test fails until its
entry is removed, so the list can't go stale.
