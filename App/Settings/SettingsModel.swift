import AppKit
import PeepCore

/// What the Settings window (#36) shows and changes: the app's existing preferences, read from
/// and written to the stores that own them, so nothing is stored twice.
///
/// | Setting | Store | Applies |
/// | --- | --- | --- |
/// | Appearance | `AppearanceSettings.mode` | the whole app, live |
/// | Default theme | `ThemeSettings.defaultThemeID` | new windows |
/// | (Open Themes Folder) | `CustomThemeLibrary.openFolder()` (#35) | Finder |
/// | Show outline in new windows | `OutlinePreference` | new windows |
/// | Pin new windows | `WindowPinPreference` | new windows |
/// | Zoom | `ZoomSettings.defaultLevel` | new windows (#47) |
/// | Content width | `ContentWidthSettings.defaultWidth` | new windows (#47) |
/// | Custom content width | `ContentWidthSettings.isCustomWidthEnabled`, `customWidthPoints` | every window, live |
/// | Default Markdown viewer | `DefaultViewer` (Launch Services) | system-wide |
/// | Default flavor | `MarkdownSettings.defaultFlavorID` | every document, live (#55) |
/// | Frontmatter display | `MarkdownSettings.frontmatterDisplay` | every document, live (#55) |
/// | Built-in preprocessors | `MarkdownSettings.builtInPreprocessors` | every document, live (#55) |
/// | Custom preprocessor | `CustomPreprocessorSettings`, via `customPreprocessor` | every document, live (#57) |
/// | Automatic update checks and downloads | Sparkle's updater, via `updater` (`SoftwareUpdating`) | the app (#81) |
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
/// method, and add a row to its pane (`GeneralSettingsView`, `MarkdownSettingsView`).
@MainActor
@Observable
final class SettingsModel: NSObject {
    @ObservationIgnored let appearanceSettings: AppearanceSettings
    @ObservationIgnored let themeSettings: ThemeSettings
    @ObservationIgnored let zoomSettings: ZoomSettings
    @ObservationIgnored let contentWidthSettings: ContentWidthSettings
    @ObservationIgnored let outlinePreference: OutlinePreference
    @ObservationIgnored let pinPreference: WindowPinPreference
    @ObservationIgnored let markdownSettings: MarkdownSettings
    @ObservationIgnored let defaultViewerOffer: DefaultViewerOfferController
    /// Sparkle's updater (#81), which owns the update settings; inactive (in memory) by default,
    /// so a model built without one never touches the reader's settings or the network.
    @ObservationIgnored let updater: any SoftwareUpdating
    /// Settings > Markdown > Custom preprocessor (#57), with its own model and store.
    @ObservationIgnored let customPreprocessor: CustomPreprocessorModel
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
    /// Whether the custom width overrides every window's content width.
    private(set) var isCustomWidthEnabled = false
    /// The custom width in px (kept while it is off).
    private(set) var customWidthPoints = CustomContentWidth.defaultPoints
    private(set) var showsOutlineInNewWindows = false
    private(set) var pinsNewWindows = false
    private(set) var isDefaultViewer = false
    /// Whether "Make Default" is waiting on Launch Services (and the button disabled).
    private(set) var isMakingDefaultViewer = false
    /// The flavors the default-flavor picker lists, in registry order (GFM first).
    private(set) var flavors: [Flavor] = []
    /// The id of the flavor documents render with unless their frontmatter names one (#54).
    private(set) var defaultFlavorID = Flavor.gfm.id
    private(set) var frontmatterDisplay = FrontmatterDisplay.hidden
    /// The built-in preprocessors that are on (a subset of `optionalPreprocessors`).
    private(set) var builtInPreprocessors: Set<MarkdownTransform> = []
    /// Whether this build checks for updates at all (`SoftwareUpdates`).
    private(set) var isUpdaterActive = false
    private(set) var automaticallyChecksForUpdates = false
    private(set) var automaticallyDownloadsUpdates = false
    /// Whether the automatic downloads row is enabled (it needs automatic checks).
    private(set) var allowsAutomaticUpdates = false

    init(
        appearanceSettings: AppearanceSettings = .shared,
        themeSettings: ThemeSettings = .shared,
        zoomSettings: ZoomSettings = .shared,
        contentWidthSettings: ContentWidthSettings = .shared,
        outlinePreference: OutlinePreference = OutlinePreference(),
        pinPreference: WindowPinPreference = WindowPinPreference(),
        markdownSettings: MarkdownSettings = .shared,
        customPreprocessor: CustomPreprocessorModel? = nil,
        updater: (any SoftwareUpdating)? = nil,
        defaultViewerOffer: DefaultViewerOfferController,
        openThemesFolder: (@MainActor () -> Void)? = nil
    ) {
        self.customPreprocessor = customPreprocessor ?? CustomPreprocessorModel()
        self.appearanceSettings = appearanceSettings
        self.themeSettings = themeSettings
        self.zoomSettings = zoomSettings
        self.contentWidthSettings = contentWidthSettings
        self.outlinePreference = outlinePreference
        self.pinPreference = pinPreference
        self.markdownSettings = markdownSettings
        self.defaultViewerOffer = defaultViewerOffer
        self.updater = updater ?? InactiveUpdater()
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
        center.addObserver(
            self, selector: refreshSelector, name: MarkdownSettings.didChangeNotification, object: markdownSettings)
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
        isCustomWidthEnabled = contentWidthSettings.isCustomWidthEnabled
        customWidthPoints = contentWidthSettings.customWidthPoints
        showsOutlineInNewWindows = outlinePreference.showsOutlineInNewWindows
        pinsNewWindows = pinPreference.pinsNewWindows
        isDefaultViewer = defaultViewerOffer.viewer.isDefault
        flavors = markdownSettings.registry.flavors
        defaultFlavorID = markdownSettings.defaultFlavorID
        frontmatterDisplay = markdownSettings.frontmatterDisplay
        builtInPreprocessors = markdownSettings.builtInPreprocessors
        customPreprocessor.refresh()
        isUpdaterActive = updater.isActive
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        allowsAutomaticUpdates = updater.allowsAutomaticUpdates
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

    /// Every window uses the custom width (or goes back to its own preset), live.
    func setCustomWidthEnabled(_ enabled: Bool) {
        contentWidthSettings.isCustomWidthEnabled = enabled
        refresh()
    }

    /// Sets the custom width, clamped to `CustomContentWidth.range`; windows follow it while it is on.
    func setCustomWidthPoints(_ points: Int) {
        contentWidthSettings.customWidthPoints = points
        refresh()
    }

    /// New windows show (or hide) the outline. Open windows keep theirs.
    func setShowsOutlineInNewWindows(_ shows: Bool) {
        outlinePreference.showsOutlineInNewWindows = shows
        refresh()
    }

    /// New windows open pinned (or not). Open windows keep theirs.
    func setPinsNewWindows(_ pins: Bool) {
        pinPreference.pinsNewWindows = pins
        refresh()
    }

    /// Documents render with the flavor with `id` (unless their frontmatter names one, #54).
    /// Open documents render again in place. An unregistered id is ignored.
    func setDefaultFlavor(id: String) {
        markdownSettings.defaultFlavorID = id
        refresh()
    }

    /// Documents show (or hide) their frontmatter. Open documents render again in place.
    func setFrontmatterDisplay(_ display: FrontmatterDisplay) {
        markdownSettings.frontmatterDisplay = display
        refresh()
    }

    /// The built-in preprocessors Settings offers (`MarkdownSettings.optionalPreprocessors`).
    var optionalPreprocessors: [MarkdownTransform] { MarkdownSettings.optionalPreprocessors }

    /// Turns a built-in preprocessor on or off. Open documents render again in place.
    func setBuiltInPreprocessor(_ preprocessor: MarkdownTransform, isOn: Bool) {
        var enabled = markdownSettings.builtInPreprocessors
        if isOn {
            enabled.insert(preprocessor)
        } else {
            enabled.remove(preprocessor)
        }
        markdownSettings.builtInPreprocessors = enabled
        refresh()
    }

    /// Sparkle checks for updates once a day (or stops). Sparkle stores it.
    func setAutomaticallyChecksForUpdates(_ checks: Bool) {
        updater.automaticallyChecksForUpdates = checks
        refresh()
    }

    /// Updates found by automatic checks download and install on their own (or ask first).
    func setAutomaticallyDownloadsUpdates(_ downloads: Bool) {
        updater.automaticallyDownloadsUpdates = downloads
        refresh()
    }

    /// Makes Peep the default Markdown viewer (the system may ask to confirm); a failure shows
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
