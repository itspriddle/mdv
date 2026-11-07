import AppKit
import SwiftUI

/// Shows the offer to become the default Markdown viewer in a small non-modal panel, and runs
/// Settings' "Make mdv the Default Markdown Viewer". The policy lives in `DefaultViewer`.
@MainActor
final class DefaultViewerOfferController: NSObject {
    let viewer: DefaultViewer
    private var panel: NSPanel?
    private var observer: (any NSObjectProtocol)?

    init(viewer: DefaultViewer = DefaultViewer()) {
        self.viewer = viewer
    }

    /// Offers when a document window first becomes key (so not over the launch Open panel).
    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let isDocumentWindow = (notification.object as? NSWindow)?.windowController is DocumentWindowController
            MainActor.assumeIsolated {
                if isDocumentWindow {
                    self?.offerIfNeeded()
                }
            }
        }
    }

    func offerIfNeeded() {
        guard panel == nil, viewer.shouldOffer else {
            return
        }
        viewer.offerShown()
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: true)
        panel.title = "Default Markdown Viewer"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(
            rootView: DefaultViewerOfferView { [weak self] choice in self?.answer(choice) })
        panel.center()
        panel.orderFront(nil)
        self.panel = panel
    }

    private func answer(_ choice: DefaultViewer.Choice) {
        panel?.close()
        panel = nil
        Task {
            do {
                try await viewer.respond(choice)
            } catch {
                Self.reportFailure(error)
            }
        }
    }

    /// Settings > General, "Make mdv the Default Markdown Viewer" (#36): closes the offer if it
    /// is showing, makes mdv the default, and shows an alert if that fails.
    func makeDefault() async {
        panel?.close()
        panel = nil
        do {
            try await viewer.makeDefault()
        } catch {
            Self.reportFailure(error)
        }
    }

    private static func reportFailure(_ error: any Error) {
        let alert = NSAlert()
        alert.messageText = "mdv couldn’t become the default Markdown viewer."
        alert.informativeText =
            "You can choose it in Finder: select a Markdown file, choose File > Get Info, and use "
            + "“Open with”. (\(error.localizedDescription))"
        alert.alertStyle = .warning
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

/// The offer's content.
private struct DefaultViewerOfferView: View {
    let answer: (DefaultViewer.Choice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Make mdv your default Markdown viewer?").font(.headline)
            Text("Markdown files you double-click in Finder will open in mdv.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Don’t Ask Again") { answer(.dontAskAgain) }
                Spacer()
                Button("Not Now") { answer(.notNow) }.keyboardShortcut(.cancelAction)
                Button("Make Default") { answer(.makeDefault) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
