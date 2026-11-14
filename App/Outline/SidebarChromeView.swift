import AppKit

/// The outline's view, drawn behind its content: the window's theme background over the system's sidebar material, and a
/// 1 pt line along the trailing edge in the theme's border color (the split view draws no
/// divider beside a sidebar). `DocumentWindowController.applyWindowChrome()` sets the colors.
final class SidebarChromeView: NSView {
    private let fill = SidebarChromeView.box()
    private let edge = SidebarChromeView.box()

    /// The sidebar's fill, the window's theme background.
    var backgroundColor: NSColor {
        get { fill.fillColor }
        set { fill.fillColor = newValue }
    }

    /// The sidebar's trailing edge, the theme's border color.
    var borderColor: NSColor {
        get { edge.fillColor }
        set { edge.fillColor = newValue }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for box in [fill, edge] {
            box.translatesAutoresizingMaskIntoConstraints = false
            addSubview(box)
        }
        NSLayoutConstraint.activate([
            fill.topAnchor.constraint(equalTo: topAnchor),
            fill.bottomAnchor.constraint(equalTo: bottomAnchor),
            fill.leadingAnchor.constraint(equalTo: leadingAnchor),
            fill.trailingAnchor.constraint(equalTo: trailingAnchor),
            edge.topAnchor.constraint(equalTo: topAnchor),
            edge.bottomAnchor.constraint(equalTo: bottomAnchor),
            edge.trailingAnchor.constraint(equalTo: trailingAnchor),
            edge.widthAnchor.constraint(equalToConstant: 1),
        ])
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SidebarChromeView is created in code")
    }

    private static func box() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 0
        box.titlePosition = .noTitle
        box.contentViewMargins = .zero
        return box
    }
}
