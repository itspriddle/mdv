import AppKit
import MdvCore

/// What Settings > Markdown > Custom preprocessor (#57) shows and changes, over
/// `CustomPreprocessorSettings`. Part of `SettingsModel` (`customPreprocessor`).
///
/// Turning the preprocessor on always goes through the warning: `setEnabled(true)` only shows
/// it (`isConfirmingEnable`), and `confirmEnable()`, the warning's "Turn On" button, is what
/// turns it on. The executable comes only from an Open panel (`chooseExecutable()`), and a
/// choice that isn't a usable executable is refused with the reason.
@MainActor
@Observable
final class CustomPreprocessorModel: NSObject {
    /// Asks the reader for a file; `nil` when they cancel. Tests pass their own.
    typealias FileChooser = @MainActor () async -> URL?

    @ObservationIgnored let settings: CustomPreprocessorSettings
    @ObservationIgnored private let chooseFile: FileChooser

    private(set) var isEnabled = false
    private(set) var executablePath: String?
    private(set) var arguments: [String] = []
    /// Why the stored executable can't run now (it was deleted, or lost its execute bit);
    /// `nil` when it can, or when there is none. Checked again each time Settings refreshes.
    private(set) var executableProblem: String?
    /// Why the last Open panel choice was refused; cleared by the next choice or a reset.
    private(set) var rejectedChoice: String?
    private(set) var lastRun: CustomPreprocessorRun?
    /// Whether the warning before turning the preprocessor on is showing. The alert's binding
    /// sets it back to `false` when it closes.
    var isConfirmingEnable = false

    init(settings: CustomPreprocessorSettings = .shared, chooseFile: FileChooser? = nil) {
        self.settings = settings
        self.chooseFile = chooseFile ?? Self.runOpenPanel
        super.init()
        refresh()
        let center = NotificationCenter.default
        let selector = #selector(settingsDidChange(_:))
        center.addObserver(
            self, selector: selector, name: CustomPreprocessorSettings.didChangeNotification, object: settings)
        center.addObserver(
            self, selector: selector, name: CustomPreprocessorSettings.lastRunDidChangeNotification, object: settings)
    }

    @objc private func settingsDidChange(_ notification: Notification) {
        refresh()
    }

    /// Reads the settings again and checks the executable.
    func refresh() {
        isEnabled = settings.isEnabled
        executablePath = settings.executablePath
        arguments = settings.arguments
        lastRun = settings.lastRun
        executableProblem = executablePath.flatMap { path in
            do throws(PreprocessorExecutableError) {
                _ = try PreprocessorConfiguration(executablePath: path)
                return nil
            } catch {
                return error.description
            }
        }
    }

    /// The program's file name, for display.
    var executableName: String? {
        executablePath.map { URL(filePath: $0).lastPathComponent }
    }

    // MARK: Changes

    /// Turning on shows the warning (`isConfirmingEnable`); turning off is immediate. Open
    /// documents render again without the preprocessor.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard !isEnabled, executablePath != nil else {
                return
            }
            isConfirmingEnable = true
        } else {
            settings.isEnabled = false
            refresh()
        }
    }

    /// The warning's "Turn On": open documents render again through the preprocessor.
    func confirmEnable() {
        isConfirmingEnable = false
        settings.isEnabled = true
        refresh()
    }

    /// The warning's "Cancel": the preprocessor stays off.
    func cancelEnable() {
        isConfirmingEnable = false
    }

    /// Shows the Open panel and uses the chosen file (`useExecutable(at:)`).
    func chooseExecutable() async {
        guard let url = await chooseFile() else {
            return
        }
        useExecutable(at: url)
    }

    /// Uses the file at `url` (from the Open panel) as the executable if it is one; otherwise
    /// keeps the current one and says why (`rejectedChoice`). When the preprocessor is on, open
    /// documents render again with the new program.
    func useExecutable(at url: URL) {
        let path = url.path(percentEncoded: false)
        do throws(PreprocessorExecutableError) {
            let configuration = try PreprocessorConfiguration(executablePath: path)
            rejectedChoice = nil
            settings.executablePath = configuration.executablePath
        } catch {
            rejectedChoice = error.description
        }
        refresh()
    }

    /// Sets the arguments, dropping empty ones. When the preprocessor is on, open documents
    /// render again.
    func setArguments(_ arguments: [String]) {
        settings.arguments = Self.committed(arguments)
        refresh()
    }

    /// Turns the preprocessor off and forgets the program and its arguments.
    func reset() {
        rejectedChoice = nil
        settings.reset()
        refresh()
    }

    /// The arguments that `arguments` (as edited) store: empty ones dropped.
    static func committed(_ arguments: [String]) -> [String] {
        arguments.filter { !$0.isEmpty }
    }

    /// An Open panel for one file, as a sheet on the key window (Settings). Links are kept as
    /// chosen, not resolved, so a Homebrew link (`/opt/homebrew/bin/x`) keeps working after an
    /// upgrade moves its target.
    private static func runOpenPanel() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "Choose the program mdv runs on each document before rendering it."
        panel.prompt = "Choose"
        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        return response == .OK ? panel.url : nil
    }
}
