import PeepCore
import Testing

@testable import PeepApp

@MainActor
@Suite("RemoteImageOptIn")
struct RemoteImageOptInTests {
    static func images(_ urls: [String]) -> [RemoteImage] {
        urls.compactMap(RemoteImage.init(source:))
    }

    @Test(
        "the bar names the hosts of images that would load",
        arguments: [
            (["https://a.example/1.png"], "1 image from a.example"),
            (["https://a.example/1.png", "https://a.example/2.png"], "2 images from a.example"),
            (
                ["https://a.example/1", "http://b.example/2", "https://c.example/3"],
                "2 images from a.example and c.example"
            ),
            (
                ["https://a.example/", "https://b.example/", "https://c.example/"],
                "3 images from a.example, b.example, and c.example"
            ),
            (
                ["https://a.example/", "https://b.example/", "https://c.example/", "https://d.example/"],
                "4 images from a.example, b.example, c.example, and 1 more"
            ),
            (["https:?query"], "1 image"),
        ])
    func detail(urls: [String], detail: String) {
        #expect(RemoteImageSummary(blocked: Self.images(urls)).detail == detail)
    }

    @Test("the bar shows until the window opts in, and never for http-only pages")
    func bar() {
        let optIn = RemoteImageOptIn()
        let page = DocumentContent(source: "![a](https://a.example/a.png)", fallbackTitle: "a.md").page
        #expect(optIn.bar(for: page)?.loadableCount == 1)
        #expect(optIn.bar(for: nil) == nil)
        let httpOnly = DocumentContent(source: "![a](http://a.example/a.png)", fallbackTitle: "a.md").page
        #expect(optIn.bar(for: httpOnly) == nil)
        optIn.allow()
        #expect(optIn.isAllowed)
        #expect(optIn.bar(for: page) == nil)
    }

    @Test("documents render blocked by default, with an opt-in page only when it would differ")
    func pages() {
        let content = DocumentContent(source: "![a](https://a.example/a.png) ![b](b.png)", fallbackTitle: "a.md")
        #expect(content.page.contentSecurityPolicy == .viewer)
        #expect(content.page.html(theme: .github).contains(ContentSecurityPolicy.viewer.header))
        #expect(content.page.body.contains("class=\"remote-image\""))
        #expect(!content.page.body.contains("https://a.example/a.png\" alt"))
        let optedIn = content.page(allowingRemoteImages: true)
        #expect(optedIn.contentSecurityPolicy == .viewerAllowingRemoteImages)
        #expect(optedIn.html(theme: .github).contains(ContentSecurityPolicy.viewerAllowingRemoteImages.header))
        #expect(optedIn.body.contains("<img src=\"https://a.example/a.png\" alt=\"a\""))
        #expect(optedIn.blockedRemoteImages.isEmpty)
        #expect(content.page(allowingRemoteImages: false) == content.page)

        let local = DocumentContent(source: "![b](b.png)", fallbackTitle: "a.md")
        #expect(local.remoteImagesPage == nil)
        #expect(local.page(allowingRemoteImages: true) == local.page)
    }
}
