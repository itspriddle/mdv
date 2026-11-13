import AppKit
import PeepCore

/// App menu > About Peep: the standard About panel, with the third-party notices (#85) as its
/// credits. They're built from the bundle's `Acknowledgements/` and `Vendor/` folders
/// (`Acknowledgements`), not imported from HTML, so nothing is fetched and the text follows the
/// appearance.
@MainActor
enum AboutPanel {
    static func show() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let credits = credits() {
            options[.credits] = credits
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    /// The credits from `bundle`'s resources, or nil (logged) if they can't be read.
    static func credits(bundle: Bundle = .main) -> NSAttributedString? {
        guard let root = bundle.resourceURL else { return nil }
        do {
            let acknowledgements = try Acknowledgements(root: root)
            let licenses = try acknowledgements.components.map {
                try Acknowledgements.licenseText(of: $0, root: root)
            }
            return credits(for: acknowledgements.components, licenses: licenses)
        } catch {
            NSLog("peep: can't read the acknowledgements: %@", String(describing: error))
            return nil
        }
    }

    /// A summary line per component, then each license's text, reflowed for the narrow panel.
    static func credits(for components: [Acknowledgement], licenses: [String]) -> NSAttributedString {
        let text = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let bold = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        func append(_ string: String, font: NSFont = body, color: NSColor = .labelColor, link: URL? = nil) {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraphStyle,
            ]
            if let link {
                attributes[.link] = link
            }
            text.append(NSAttributedString(string: string, attributes: attributes))
        }

        append("Peep includes the following third-party software.\n\n", color: .secondaryLabelColor)
        for component in components {
            append(component.name, font: bold, link: URL(string: component.homepage))
            append(" \u{2014} \(component.use) (\(component.license))\n", color: .secondaryLabelColor)
        }
        for (component, license) in zip(components, licenses) {
            append("\n\(component.name)\n", font: bold)
            for paragraph in Acknowledgements.paragraphs(of: license) {
                append(paragraph + "\n", color: .secondaryLabelColor)
            }
        }
        return text
    }

    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 4
        return style
    }()
}
