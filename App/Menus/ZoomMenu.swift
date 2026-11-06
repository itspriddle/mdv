import AppKit

/// View > Zoom In (Command-+), Zoom Out (Command-minus), and Actual Size (Command-0). A hidden
/// duplicate of Zoom In answers Command-= so the shortcut works without Shift. Actions are on
/// `DocumentWindowController` (`+Zoom.swift`), so they're disabled without a document window.
enum ZoomMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        let zoomInWithoutShift = NSMenuItem(
            "Zoom In", action: #selector(DocumentWindowController.zoomInDocument(_:)), key: "=")
        zoomInWithoutShift.isHidden = true
        zoomInWithoutShift.allowsKeyEquivalentWhenHidden = true
        menu.addGroup(
            [
                NSMenuItem("Actual Size", action: #selector(DocumentWindowController.resetDocumentZoom(_:)), key: "0"),
                NSMenuItem("Zoom In", action: #selector(DocumentWindowController.zoomInDocument(_:)), key: "+"),
                zoomInWithoutShift,
                NSMenuItem("Zoom Out", action: #selector(DocumentWindowController.zoomOutDocument(_:)), key: "-"),
            ], to: .view)
    }
}
