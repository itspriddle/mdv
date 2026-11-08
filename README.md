# mdv

A fast, native Markdown viewer for macOS, with a command-line companion.

```sh
mdv README.md
echo '# Markdown' | mdv
mdv --html README.md > README.html
```

> **Status:** early development. `mdv` is a working name. See [docs/VISION.md](docs/VISION.md) and
> [docs/ROADMAP.md](docs/ROADMAP.md).

## Themes

mdv ships GitHub, Document, and Serif themes, and any CSS file in
`~/Library/Application Support/mdv/Themes` is a theme too. See the
[theme authoring guide](docs/THEMES.md).

## Per-document settings

A document can choose how it is shown with an `mdv:` mapping in its YAML frontmatter:

```yaml
---
mdv:
  flavor: commonmark   # or gfm (the default)
  theme: serif         # a bundled id, or custom:<file name>
  wikilinks: true      # [[Page]] links, once wiki links ship (#53)
---
```

- `flavor` is applied before the body is parsed, in the app and in `mdv --html`. An unknown
  flavor is ignored, and the document renders with the default.
- `theme` beats the default theme from Settings, but a theme you pick for the window in View >
  Theme beats it (View > Theme > Document's Theme goes back). See the
  [theme guide](docs/THEMES.md#choosing-a-theme-per-document).
- **What a document can't do:** these are the only keys. A document is untrusted input, so it
  can only choose among presentation options. It can't turn on the custom preprocessor, turn
  off HTML sanitizing, load remote images, or change any other safety setting. Other keys and
  values of the wrong type are ignored (and reported to the renderer, never shown as an error).
- Only YAML frontmatter (`---`) is read. TOML frontmatter (`+++`) is detected and hidden but not
  parsed, so `[mdv]` in TOML has no effect.

## Custom preprocessor

mdv can run a program of your choice on every document before rendering it, for formats or
conventions it doesn't know. It is off by default. Turn it on in Settings > Markdown > Custom
preprocessor: choose the program with Choose… and add any arguments, one per field.

- The program gets the document on standard input and writes Markdown to standard output; exit
  status 0 means success. The document's path is in `MDV_DOCUMENT_PATH`, and it runs in the
  document's folder with a minimal environment. Arguments are passed as given, with no shell.
- It runs as you, with your access to files, on every document you open. Only use a program you
  trust. A document can't turn it on or change it.
- It has 5 seconds and 10 MB of output. If it fails, the window shows the document without it
  and a bar with the reason; Show Details has what the program wrote to standard error.
- It runs again on every live reload, and open windows update when you change it in Settings.

## Requirements

- macOS 15 or later
- Xcode 26+ (Swift 6) to build from source

## Building

```sh
make bootstrap     # brew install xcodegen swiftlint
make generate      # create mdv.xcodeproj from project.yml (the project file is not committed)
open mdv.xcodeproj
```

Signed local builds: copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your
`DEVELOPMENT_TEAM`. Without it, build unsigned with `make build SIGN=0`.

| Command            | What it does                               |
| ------------------ | ------------------------------------------ |
| `make build`       | Build the app and embedded CLI             |
| `make test`        | Run core (`swift test`) and app test suites |
| `make lint`        | SwiftLint + swift-format lint (strict)     |
| `make format`      | Auto-format sources                        |

## Project layout

| Path               | Contents                                                       |
| ------------------ | -------------------------------------------------------------- |
| `Sources/MdvCore`  | Rendering engine (Swift package, UI-free, fully unit-tested)   |
| `App`              | SwiftUI macOS app                                              |
| `CLI`              | `mdv` command-line tool, embedded in `mdv.app/Contents/Helpers` |
| `project.yml`      | XcodeGen spec for the app, CLI, and app tests                  |

## License

[MIT](LICENSE)
