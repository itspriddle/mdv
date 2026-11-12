import XCTest

extension PeepUITestApp {
    /// The launch arguments that start the app with fixture script `name` (in
    /// `Fixtures/preprocessors`) as its custom preprocessor (#57).
    ///
    /// The scripts are bundle fixtures (executable in git) rather than files the test writes:
    /// the runner is sandboxed, files it writes are quarantined, and the system refuses to run
    /// a quarantined script (`EPERM`), as it would a downloaded one.
    static func preprocessorArguments(fixture name: String) throws -> [String] {
        ["-PeepUITestPreprocessor", try Fixtures.url(named: "preprocessors/\(name)").path(percentEncoded: false)]
    }

    /// The custom preprocessor's failure bar in `window`.
    func preprocessorFailureBar(in window: XCUIElement) -> XCUIElement {
        window.descendants(matching: .any)["preprocessor-failure-bar"].firstMatch
    }
}
