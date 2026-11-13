# Contributing to Peep

Thanks for your interest in Peep. Bug reports, feature ideas, and pull requests are welcome.

Before planning a change, read [docs/VISION.md](docs/VISION.md) (principles, architecture, and
the security model) and [docs/ROADMAP.md](docs/ROADMAP.md) (what's planned, and in what order).
For anything bigger than a small fix, open an issue first so we can agree on the approach.

Security problems are different: please don't open a public issue. See
[SECURITY.md](SECURITY.md).

## Setting up

You need macOS 15 or later and Xcode 26 or later (Swift 6).

```sh
make bootstrap   # brew install xcodegen swiftlint
make generate    # create Peep.xcodeproj from project.yml
open Peep.xcodeproj
```

`Peep.xcodeproj` is generated and never committed: change `project.yml` instead, and run
`make generate` again after adding or removing files.

To sign local builds, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set
your `DEVELOPMENT_TEAM`. That file is ignored by Git; never commit it or a team ID. Without it,
build unsigned with `make build SIGN=0`.

## Building and testing

| Command          | What it does                                                        |
| ---------------- | ------------------------------------------------------------------- |
| `make build`     | Build the app with the embedded `peep` CLI                          |
| `make test-core` | Core and CLI tests with `swift test` (no Xcode project needed)      |
| `make test`      | Core tests plus the app's unit tests                                |
| `make test-ui`   | UI tests, which drive the app (see below)                           |
| `make lint`      | SwiftLint and swift-format in strict mode, as CI runs them          |
| `make format`    | Format the sources; run it before committing                        |

`swift run peep --html FILE` renders a file to standard output without building the app.

Most logic belongs in `Sources/PeepCore` (no UI imports) so it can be tested with `swift test`;
the app in `App/` and the CLI in `CLI/` stay thin. Tests use Swift Testing (`@Test`,
`#expect`); UI tests use XCTest. A user-facing feature comes with a UI test.

UI tests run the real app and must be code signed (`make test-ui` signs with your team, or ad
hoc). The app you run them from (Terminal, iTerm, your editor) needs System Settings > Privacy
& Security > Developer Tools, and the first run asks to give `AppUITests-Runner` Accessibility
access.

## Code style

- Swift 6 language mode with strict concurrency; macOS 15 is the minimum.
- `make lint` must report zero violations. swift-format owns layout; SwiftLint owns code smells.
- No force unwraps: use failable APIs and throw on bad input.
- Keep the security defaults in [docs/VISION.md](docs/VISION.md): strict CSP, no remote content,
  JavaScript off or bundle-only, sanitized raw HTML.
- Check that a dependency exists, and its latest version, before adding it.

## Third-party code

Every bundled third-party component needs a notice. Add an entry to
`Acknowledgements/Acknowledgements.json` with its license text, copied from the project's own
license file (not retyped), in `Acknowledgements/` or the component's `Vendor/` folder. The
About panel shows the list, and a test fails if a vendored folder or linked package has no entry.

## Branches, commits, and pull requests

- Work on one issue per branch, named with
  [Conventional Branch](https://conventional-branch.github.io) prefixes: `feature/gfm-tables`,
  `bugfix/outline-scroll`, `chore/update-yams`.
- Write commit messages with [Conventional Commits](https://www.conventionalcommits.org):
  `feat(cli): add --wait`, `fix(app): keep the reading position on reload`,
  `docs: explain custom themes`.
- Open the pull request against `main` unless the issue says otherwise (milestone work merges
  into the milestone's integration branch first). CI runs lint, the core tests, the app build
  and tests, and the UI tests; all must pass.
- Describe what changed and why, and link the issue (`Closes #123`).

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
