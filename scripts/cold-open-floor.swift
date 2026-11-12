// The floor for cold open to first paint with WKWebView (#40), built and run by
// `scripts/measure-cold-open -f`: a bare AppKit app that, first thing at launch, loads a
// prerendered page (`peep --html FILE`, the argument) into one WKWebView configured like Peep's
// (page JavaScript off, non-persistent data store) in one plain window. No document
// architecture, menus, toolbar, sidebar, or SwiftUI. It reports milliseconds from process start
// to two animation frames after the load finished, in Peep's `LaunchTiming` format, and quits.
import AppKit
import Darwin
import WebKit

func processStart() -> Double {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
    let start = info.kp_proc.p_un.__p_starttime
    return Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
}

func sinceStart() -> Double {
    var now = timeval()
    gettimeofday(&now, nil)
    return (Double(now.tv_sec) + Double(now.tv_usec) / 1_000_000 - processStart()) * 1000
}

@MainActor
final class Delegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow?
    var webView: WKWebView?
    var marks: [String] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        marks.append(String(format: "\"willFinishLaunching\":%.1f", sinceStart()))
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 760), configuration: configuration)
        webView.navigationDelegate = self
        let html = (try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)) ?? ""
        webView.loadHTMLString(html, baseURL: nil)
        marks.append(String(format: "\"loadStarted\":%.1f", sinceStart()))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        self.webView = webView
        marks.append(String(format: "\"windowShown\":%.1f", sinceStart()))
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        marks.append(String(format: "\"pageLoaded\":%.1f", sinceStart()))
        Task {
            _ = try? await webView.callAsyncJavaScript(
                "for (let i = 0; i < 2; i++) { await new Promise(r => requestAnimationFrame(r)); }",
                arguments: [:], in: nil, contentWorld: .defaultClient)
            marks.append(String(format: "\"painted\":%.1f", sinceStart()))
            FileHandle.standardError.write(Data("peep-launch-timing {\(marks.joined(separator: ","))}\n".utf8))
            NSApplication.shared.terminate(nil)
        }
    }
}

let delegate = MainActor.assumeIsolated { Delegate() }
MainActor.assumeIsolated {
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.run()
}
