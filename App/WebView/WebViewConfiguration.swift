import WebKit

/// Builds the configuration every document web view uses. Everything that must be decided
/// before a `WKWebView` exists (preferences, content worlds, user scripts, URL scheme handlers)
/// goes here; WebKit copies the configuration at creation time.
@MainActor
enum WebViewConfiguration {
    static func make() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        // Page JavaScript is off: document `<script>`s, inline handlers, and `javascript:` URLs
        // never run. App scripts still run, in `AppScripts.world` (see VISION's security model).
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.isElementFullscreenEnabled = false
        for script in AppScripts.userScripts {
            configuration.userContentController.addUserScript(script)
        }
        // The `mdv-doc` scheme handler is per window: `WebViewCoordinator.init` installs it.
        return configuration
    }
}
