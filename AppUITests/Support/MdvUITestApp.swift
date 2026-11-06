import XCTest

/// Drives mdv in UI tests: launches it in UI-test mode (see `UITestHooks` in the app) and finds
/// the document UI.
///
/// Features extend this type with their own finders and actions in
/// `AppUITests/Support/MdvUITestApp+<Feature>.swift`.
@MainActor
struct MdvUITestApp {
    /// How long to wait for a window or rendered content to appear.
    static let defaultTimeout: TimeInterval = 10

    /// The `WKWebView`'s accessibility identifier (set by the app's `WebViewCoordinator`).
    static let webViewIdentifier = "document-web-view"

    let app: XCUIApplication

    /// Launches a fresh mdv, optionally opening `document`.
    ///
    /// Every launch sets `-MdvUITesting YES` (no Open panel at launch, no first-run prompts) and,
    /// unless `restoresState`, `-ApplePersistenceIgnoreState YES` (no restored windows from
    /// earlier runs; state is written to a temporary folder). `restoresState` instead saves and
    /// restores windows for real, even when quitting with Cmd-Q (`NSQuitAlwaysKeepsWindows`).
    @discardableResult
    static func launch(
        opening document: URL? = nil,
        arguments: [String] = [],
        environment: [String: String] = [:],
        restoresState: Bool = false
    ) -> MdvUITestApp {
        let app = XCUIApplication()
        app.launchArguments = ["-MdvUITesting", "YES"]
        app.launchArguments +=
            restoresState
            ? ["-ApplePersistenceIgnoreState", "NO", "-NSQuitAlwaysKeepsWindows", "YES"]
            : ["-ApplePersistenceIgnoreState", "YES"]
        if let document {
            app.launchArguments += ["-MdvUITestOpen", document.path(percentEncoded: false)]
        }
        app.launchArguments += arguments
        app.launchEnvironment.merge(environment) { _, new in new }
        // Sanitizer runs (`TEST_RUNNER_ASAN_OPTIONS=… xcodebuild -enableAddressSanitizer YES`):
        // give the app the runner's options, so a report prints instead of a crash dialog.
        for key in ["ASAN_OPTIONS", "TSAN_OPTIONS"] where app.launchEnvironment[key] == nil {
            app.launchEnvironment[key] = ProcessInfo.processInfo.environment[key]
        }
        app.launch()
        return MdvUITestApp(app: app)
    }

    /// Launches mdv opening the named fixture from `AppUITests/Fixtures`.
    @discardableResult
    static func launch(openingFixture name: String, arguments: [String] = []) throws -> MdvUITestApp {
        launch(opening: try Fixtures.url(named: name), arguments: arguments)
    }

    /// The window with the given title.
    func window(titled title: String) -> XCUIElement {
        app.windows[title]
    }

    /// The frontmost window.
    var frontWindow: XCUIElement {
        app.windows.firstMatch
    }

    /// The document web view in `window` (default: the frontmost window): the web area holding
    /// the rendered page.
    ///
    /// The app's identifier lands on the `WKWebView` itself, which the accessibility tree shows
    /// as a group (`webViewContainer(in:)`); WebKit nests the page's web area (type `.webView`)
    /// inside it, under a scroll area. The web area's frame is the whole scrollable page, not the
    /// visible part.
    func webView(in window: XCUIElement? = nil) -> XCUIElement {
        webViewContainer(in: window).descendants(matching: .webView).firstMatch
    }

    /// The `WKWebView` in `window` (identifier `document-web-view`). Its frame is the visible
    /// area of the page.
    func webViewContainer(in window: XCUIElement? = nil) -> XCUIElement {
        (window ?? frontWindow).descendants(matching: .any)[Self.webViewIdentifier].firstMatch
    }

    /// Waits for a window with `title` and returns it, failing the test if it never appears.
    @discardableResult
    func waitForWindow(
        titled title: String,
        timeout: TimeInterval = defaultTimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let window = window(titled: title)
        if !window.waitForExistence(timeout: timeout) {
            let titles = app.windows.allElementsBoundByIndex.map(\.title)
            XCTFail("No window titled \"\(title)\"; windows: \(titles)", file: file, line: line)
        }
        return window
    }

    /// Waits for rendered text containing `text` in the web view of `window`, failing the test
    /// if it never appears.
    ///
    /// Matching is on the accessibility label or value, so `text` must lie within one text run
    /// (inline markup like `**bold**` splits a paragraph into several elements).
    @discardableResult
    func waitForRenderedText(
        _ text: String,
        in window: XCUIElement? = nil,
        timeout: TimeInterval = defaultTimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let element = renderedText(text, in: window)
        if !element.waitForExistence(timeout: timeout) {
            XCTFail("Rendered text \"\(text)\" not found in the web view", file: file, line: line)
        }
        return element
    }

    /// The first element in the web view whose label or value contains `text`.
    func renderedText(_ text: String, in window: XCUIElement? = nil) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        return webView(in: window).descendants(matching: .any).matching(predicate).firstMatch
    }

    func terminate() {
        app.terminate()
    }
}

extension XCUIElement {
    /// The text the element shows: its value when that is a non-empty string, else its label.
    /// Static text (SwiftUI `Text`, WebKit text runs) exposes its string as the value, even when
    /// it has an accessibility label; buttons and images use the label.
    var displayedText: String {
        if let value = value as? String, !value.isEmpty {
            return value
        }
        return label
    }
}

/// Fixture documents bundled from `AppUITests/Fixtures` (a folder reference in project.yml).
enum Fixtures {
    enum MissingFixture: Error {
        case notFound(String)
    }

    private final class BundleToken {}

    /// The URL of `name` (e.g. `"smoke.md"`) in the test bundle's `Fixtures` folder.
    static func url(named name: String) throws -> URL {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw MissingFixture.notFound(name)
        }
        return url
    }
}
