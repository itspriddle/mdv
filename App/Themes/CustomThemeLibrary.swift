import AppKit
import PeepCore
import os

/// Custom themes (#35): the `.css` files in `~/Library/Application Support/Peep/Themes`,
/// loaded at launch and again whenever the folder changes, without a restart.
///
/// `ThemeFolderWatcher` reports changes (debounced, off the main thread); each report reads
/// the folder there too (`CustomThemeFolder.load`) and hands the catalog to the main actor,
/// where `ThemeSettings.apply(_:)` replaces the registry. Windows showing a theme that changed
/// swap it in place (#34); a theme whose file is gone falls back to the default, and comes
/// back if the file does. Files that don't load are listed, disabled, in the theme picker with
/// the reason (and logged), never shown as an alert.
///
/// The folder isn't created until the reader asks for it (View > Theme > Open Themes Folder,
/// `openFolder()`); a missing folder is watched for, so creating it by hand works too.
@MainActor
final class CustomThemeLibrary {
    /// The folder under Application Support that holds Peep's files.
    static let applicationSupportFolderName = "Peep"

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "peep", category: "themes")
    /// The themes folder's name inside it.
    static let themesFolderName = "Themes"

    let folder: URL
    private let settings: ThemeSettings
    private var watcher: ThemeFolderWatcher?

    init(folder: URL, settings: ThemeSettings, timing: ThemeFolderWatcher.Timing = .init()) {
        self.folder = folder
        self.settings = settings
        let themes = CustomThemeFolder(url: folder)
        let base = settings.baseRegistry
        watcher = ThemeFolderWatcher(folder: folder, timing: timing) { [weak self] in
            let catalog = themes.load(base: base)
            // `DispatchQueue.main` is FIFO, so an older scan never lands after a newer one.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.apply(catalog)
                }
            }
        }
    }

    /// The real themes folder, the UI test's folder (`UITestHooks.themesFolder`), or nil
    /// where custom themes stay off: UI tests without a folder and hosted unit tests, so no
    /// test reads or creates the reader's folder.
    static var folderURL: URL? {
        if let override = UITestHooks.themesFolder {
            return override
        }
        guard !UITestHooks.isUITesting, !AppDelegate.isHostingUnitTests,
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            return nil
        }
        return
            support
            .appending(path: applicationSupportFolderName, directoryHint: .isDirectory)
            .appending(path: themesFolderName, directoryHint: .isDirectory)
    }

    /// Starts watching; the first load follows shortly (off the main thread).
    func start() {
        watcher?.start()
    }

    /// Stops watching. The loaded themes stay registered.
    func stop() {
        watcher?.stop()
    }

    /// Reads the folder again soon.
    func reload() {
        watcher?.checkForChanges()
    }

    /// Creates the folder if needed and shows it in Finder (not under UI tests). View > Theme
    /// and Settings > General (#36) both call this.
    func openFolder() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            NSApp.presentError(error)
            return
        }
        reload()
        if UITestHooks.opensLinksOutsideApp {
            NSWorkspace.shared.open(folder)
        }
    }

    private func apply(_ catalog: CustomThemeCatalog) {
        let known = Set(settings.customThemeFailures.map(\.message))
        for failure in catalog.failures where !known.contains(failure.message) {
            let name = failure.fileName
            let problem = failure.problem.description
            Self.logger.error("Custom theme \(name, privacy: .public) not loaded: \(problem, privacy: .public)")
        }
        settings.apply(catalog)
    }
}
