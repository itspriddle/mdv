import Foundation
import Testing

@testable import MdvApp

/// The web view started at launch (#40): the first window takes it, already preparing, and
/// later windows make their own.
@MainActor
@Suite("WebViewPrewarmer", .serialized, .timeLimit(.minutes(1)))
struct WebViewPrewarmerTests {
    @Test("the first window gets the prewarmed, preparing web view; the next gets a fresh one")
    func firstWindowTakesPrewarmed() async throws {
        let prewarmer = WebViewPrewarmer()
        prewarmer.prewarm()
        let first = prewarmer.takeCoordinator()
        #expect(first.expectedLoadURL == WebViewCoordinator.preparationURL, "its preparation load started")
        let deadline = ContinuousClock.now + .seconds(20)
        while first.webView.isLoading || first.webView.url == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(WebViewCoordinator.isPreparationURL(first.webView.url))
        #expect(first.expectedLoadURL == nil, "the navigation policy allowed the preparation load")
        #expect(!first.hasLoadedPage, "the preparation page is never a document page")

        let second = prewarmer.takeCoordinator()
        #expect(second !== first)
        #expect(second.expectedLoadURL == nil && second.webView.url == nil, "nothing started on the second")
    }

    @Test("prewarming happens once per launch, and taking without it makes a fresh web view")
    func oncePerLaunch() {
        let prewarmer = WebViewPrewarmer()
        let fresh = prewarmer.takeCoordinator()
        #expect(fresh.expectedLoadURL == nil)
        prewarmer.prewarm()
        let prewarmed = prewarmer.takeCoordinator()
        #expect(prewarmed.expectedLoadURL == WebViewCoordinator.preparationURL)
        prewarmer.prewarm()
        #expect(prewarmer.takeCoordinator().expectedLoadURL == nil, "a second prewarm does nothing")
    }
}
