import AppKit
import MdvCore

/// What the Settings window (#36) shows and changes: the app's existing preferences, read from
/// and written to the stores that own them, so nothing is stored twice.
///
/// | Setting | Store | Applies |
/// | --- | --- | --- |
/// | Appearance | `AppearanceSettings.mode` | the whole app, live |
/// | Default theme | `ThemeSettings.defaultThemeID` | new windows |
/// | (Open Themes Folder) | `CustomThemeLibrary.openFolder()` (#35) | Finder |
/// | Show outline in new windows | `OutlinePreference` | new windows |
/// | Zoom | `ZoomSettings.defaultLevel` | new windows (#47) |
/// | Content width | `ContentWidthSettings.defaultWidth` | new windows (#47) |
/// | Default Markdown viewer | `DefaultViewer` (Launch Services) | system-wide |
///
/// Every store takes an injectable `UserDefaults` suite and is in memory under UI tests, so
/// hosted tests build the model over throwaway stores. The model mirrors the stores in
/// observable properties and refreshes them when a store posts its change notification (View >
/// Theme registry changes) and when the Settings window
/// becomes key (`refresh()`, for the outline preference and Launch Services, which post
/// nothing). Change a setting with its `set…` method, never the property.
///
/// To add a setting: give its store an injectable `UserDefaults` (and a change notification if
/// something else can change it), add a property here, read it in `refresh()`, add a `set…`
/// method, and add a row to `GeneralSettingsView`.
@MainActor
@Observable
final class SettingsModel: NSObject {
    @ObservationIgnored let appearanceSettings: AppearanceSettings
    @ObservationIgnored let themeSettings: ThemeSettings
    @ObservationIgnored let zoomSettings: ZoomSettings
    @ObservationIgnored let contentWidthSettings: ContentWidthSettings
    @ObservationIgnored let outlinePreference: OutlinePreference
    @ObservationIgnored let defaultViewerOffer: DefaultViewerOfferController
    /// Opens the custom themes folder (#35, the same action as View > Theme > Open Themes
    /// Folder); nil where custom themes are off (hosted tests, UI tests without a folder).
    @ObservationIgnored let openThemesFolderAction: (@MainActor () -> Void)?

    private(set) var appearanceMode = AppearanceMode.system
    /// The themes the default-theme picker lists: bundled, then custom (#35), as View > Theme.
    private(set) var themeSections: [[Theme]] = []
    /// The id of the theme new windows use: the stored default, resolved in the registry (a
    /// deleted custom theme shows as the registry's default).
    private(set) var defaultThemeID = ""
    /// Custom theme files that didn't load, one line each ("Name: why").
    private(set) var themeFailures: [String] = []
    /// The zoom new windows start at, snapped to the nearest `PageZoom.levels` entry.
    private(set) var zoomLevel = PageZoom.actualSize
    /// The content width new windows start with.
    private(set) var contentWidth = ContentWidth.default
    private(set) var showsOutlineInNewWindows = false
    private(set) var isDefaultViewer = false
    /// Whether "Make Default" is waiting on Launch Services (and the button disabled).
    private(set) var isMakingDefaultViewer = false

    init(
        appearanceSettings: AppearanceSettings = .shared,
        themeSettings: ThemeSettings = .shared,
        zoomSettings: ZoomSettings = .shared,
        contentWidthSettings: ContentWidthSettings = .shared,
        outlinePreference: OutlinePreference = OutlinePreference(),
        defaultViewerOffer: DefaultViewerOfferController,
        openThemesFolder: (@MainActor () -> Void)? = nil
    ) {
        self.appearanceSettings = appearanceSettings
        self.themeSettings = themeSettings
        self.zoomSettings = zoomSettings
        self.contentWidthSettings = contentWidthSettings
        self.outlinePreference = outlinePreference
        self.defaultViewerOffer = defaultViewerOffer
        openThemesFolderAction = openThemesFolder
        super.init()
        refresh()
        let center = NotificationCenter.default
        let refreshSelector = #selector(storeDidChange(_:))
        center.addObserver(
            self, selector: refreshSelector, name: AppearanceSettings.didChangeNotification,
            object: appearanceSettings)
        center.addObserver(
            self, selector: refreshSelector, name: ThemeSettings.didChangeNotification, object: themeSettings)
        center.addObserver(
            self, selector: refreshSelector, name: ZoomSettings.didChangeNotification, object: zoomSettings)
        center.addObserver(
            self, selector: refreshSelector, name: ContentWidthSettings.didChangeNotification,
            object: contentWidthSettings)
    }

    @objc private func storeDidChange(_ notification: Notification) {
        refresh()
    }

    /// Reads every setting from its store again.
    func refresh() {
        appearanceMode = appearanceSettings.mode
        let registry = themeSettings.registry
        themeSections = registry.pickerSections()
        defaultThemeID = themeSettings.defaultTheme.id
        themeFailures = themeSettings.customThemeFailures.map(\.message)
        zoomLevel = Self.nearestZoomLevel(to: zoomSettings.defaultLevel)
        contentWidth = contentWidthSettings.defaultWidth
        showsOutlineInNewWindows = outlinePreference.showsOutlineInNewWindows
        isDefaultViewer = defaultViewerOffer.viewer.isDefault
    }

    // MARK: Changes

    /// Every window (and Settings) follows the new appearance at once.
    func setAppearanceMode(_ mode: AppearanceMode) {
        appearanceSettings.mode = mode
        refresh()
    }

    /// New windows open in the theme with `id`. Open windows keep theirs.
    func setDefaultTheme(id: String) {
        guard themeSettings.registry.contains(id: id) else {
            return
        }
        themeSettings.defaultThemeID = id
        refresh()
    }

    /// Whether "Open Themes Folder" is available.
    var canOpenThemesFolder: Bool { openThemesFolderAction != nil }

    /// Creates the custom themes folder if needed and shows it in Finder.
    func openThemesFolder() {
        openThemesFolderAction?()
    }

    /// New windows open at `level`. Open windows keep theirs.
    func setZoomLevel(_ level: Double) {
        zoomSettings.defaultLevel = level
        refresh()
    }

    /// New windows open with `width`. Open windows keep theirs.
    func setContentWidth(_ width: ContentWidth) {
        contentWidthSettings.defaultWidth = width
        refresh()
    }

    /// New windows show (or hide) the outline. Open windows keep theirs.
    func setShowsOutlineInNewWindows(_ shows: Bool) {
        outlinePreference.showsOutlineInNewWindows = shows
        refresh()
    }

    /// Makes mdv the default Markdown viewer (the system may ask to confirm); a failure shows
    /// an alert (`DefaultViewerOfferController`).
    func makeDefaultViewer() async {
        guard !isMakingDefaultViewer else {
            return
        }
        isMakingDefaultViewer = true
        await defaultViewerOffer.makeDefault()
        isMakingDefaultViewer = false
        refresh()
    }

    // MARK: Display

    /// The `PageZoom.levels` entry closest to `level`.
    static func nearestZoomLevel(to level: Double) -> Double {
        PageZoom.levels.min { abs($0 - level) < abs($1 - level) } ?? PageZoom.actualSize
    }

    /// "125%".
    static func zoomTitle(_ level: Double) -> String {
        "\(Int((level * 100).rounded()))%"
    }
}
