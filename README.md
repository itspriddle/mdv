# mdv

A fast, native Markdown viewer for macOS, with a command-line companion.

```sh
mdv README.md
echo '# Markdown' | mdv
mdv --html README.md > README.html
```

> **Status:** early development. `mdv` is a working name. See [docs/VISION.md](docs/VISION.md) and
> [docs/ROADMAP.md](docs/ROADMAP.md).

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
