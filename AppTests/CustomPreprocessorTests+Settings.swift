import AppKit
import Foundation
import PeepCore
import Testing

@testable import PeepApp

/// The custom preprocessor's store and Settings model (#57).
extension CustomPreprocessorTests {
    // MARK: Store

    @Test("off by default with nothing stored")
    func offByDefault() {
        let store = store()
        #expect(!store.isEnabled)
        #expect(store.executablePath == nil)
        #expect(store.arguments.isEmpty)
        #expect(store.preference == nil)
        #expect(store.lastRun == nil)
        for key in [
            CustomPreprocessorSettings.enabledKey, CustomPreprocessorSettings.executableKey,
            CustomPreprocessorSettings.argumentsKey,
        ] {
            #expect(defaults.object(forKey: key) == nil)
        }
        // The app's own store (in memory in hosted tests) is off too, and so are new documents.
        #expect(CustomPreprocessorSettings.shared.preference == nil)
        #expect(MarkdownDocument().renderPreferences.customPreprocessor == nil)
    }

    @Test("settings persist and reset removes them")
    func persists() throws {
        let path = try scripts.upcase()
        let store = store()
        store.executablePath = path
        store.arguments = ["--a", "two words"]
        store.isEnabled = true
        #expect(
            store.preference == CustomPreprocessorPreference(executablePath: path, arguments: ["--a", "two words"]))

        let reread = self.store()
        #expect(reread.isEnabled)
        #expect(reread.executablePath == path)
        #expect(reread.arguments == ["--a", "two words"])

        store.reset()
        #expect(store.preference == nil)
        #expect(defaults.object(forKey: CustomPreprocessorSettings.enabledKey) == nil)
        #expect(defaults.object(forKey: CustomPreprocessorSettings.executableKey) == nil)
        #expect(defaults.object(forKey: CustomPreprocessorSettings.argumentsKey) == nil)
    }

    @Test("stored values are untrusted: on only with an absolute executable")
    func untrusted() {
        let store = store()
        store.isEnabled = true
        #expect(!store.isEnabled, "no executable: stays off")
        #expect(defaults.object(forKey: CustomPreprocessorSettings.enabledKey) == nil)

        defaults.set(true, forKey: CustomPreprocessorSettings.enabledKey)
        defaults.set("bin/script", forKey: CustomPreprocessorSettings.executableKey)
        #expect(store.executablePath == nil)
        #expect(!store.isEnabled)
        #expect(store.preference == nil)

        store.executablePath = "relative/script"
        #expect(defaults.string(forKey: CustomPreprocessorSettings.executableKey) == "bin/script", "ignored")
    }

    @Test("in memory under UI tests, never touching the defaults")
    func inMemory() throws {
        let store = store(isPersistent: false)
        store.executablePath = try scripts.upcase()
        store.isEnabled = true
        #expect(store.isEnabled)
        #expect(defaults.object(forKey: CustomPreprocessorSettings.enabledKey) == nil)
        #expect(defaults.object(forKey: CustomPreprocessorSettings.executableKey) == nil)
    }

    // MARK: Settings model

    @Test("turning it on needs the warning's Turn On; Cancel keeps it off")
    func enableNeedsWarning() throws {
        let store = store()
        let model = CustomPreprocessorModel(settings: store) { nil }
        model.setEnabled(true)
        #expect(!model.isConfirmingEnable, "no program yet: nothing to turn on")

        model.useExecutable(at: URL(filePath: try scripts.upcase()))
        model.setEnabled(true)
        #expect(model.isConfirmingEnable)
        #expect(!store.isEnabled, "the warning alone doesn't turn it on")
        model.cancelEnable()
        #expect(!model.isConfirmingEnable)
        #expect(!store.isEnabled)

        model.setEnabled(true)
        model.confirmEnable()
        #expect(store.isEnabled)
        #expect(model.isEnabled)

        model.setEnabled(false)
        #expect(!store.isEnabled, "turning it off needs no warning")
    }

    @Test("the Open panel's choice must be an executable file")
    func choosesExecutable() async throws {
        let store = store()
        let notExecutable = folder.appending(path: "plain.txt")
        try Data("text".utf8).write(to: notExecutable)
        var choice: URL? = notExecutable
        let model = CustomPreprocessorModel(settings: store) { choice }

        await model.chooseExecutable()
        #expect(store.executablePath == nil)
        #expect(model.rejectedChoice?.contains("is not executable") == true)

        choice = folder
        await model.chooseExecutable()
        #expect(model.rejectedChoice?.contains("is not a file") == true)

        let script = try scripts.upcase()
        choice = URL(filePath: script)
        await model.chooseExecutable()
        #expect(store.executablePath == script)
        #expect(model.rejectedChoice == nil)
        #expect(model.executableProblem == nil)

        choice = nil  // Cancel keeps the program.
        await model.chooseExecutable()
        #expect(store.executablePath == script)

        // A program deleted later shows why it can't run.
        try FileManager.default.removeItem(atPath: script)
        model.refresh()
        #expect(model.executableProblem?.contains("doesn’t exist") == true)

        model.reset()
        #expect(store.executablePath == nil)
        #expect(model.executableProblem == nil)
    }

    @Test("arguments are kept verbatim; empty ones are dropped")
    func arguments() throws {
        let store = store()
        let model = CustomPreprocessorModel(settings: store) { nil }
        model.setArguments(["--to", "", "two words", "$HOME", "*"])
        #expect(store.arguments == ["--to", "two words", "$HOME", "*"])
        #expect(model.arguments == store.arguments)
    }

    @Test("the Settings model includes the section's model")
    func settingsModel() throws {
        let store = store()
        let section = CustomPreprocessorModel(settings: store) { nil }
        let viewer = DefaultViewer(
            workspace: FakeWorkspace(), defaults: defaults, applicationURL: URL(filePath: "/Applications/Peep.app"),
            bundleIdentifier: "now.peep.Peep", isSuppressed: true)
        let model = SettingsModel(
            appearanceSettings: AppearanceSettings(defaults: defaults, isPersistent: true),
            themeSettings: themeSettings(), zoomSettings: settings(),
            contentWidthSettings: ContentWidthSettings(defaults: defaults, isPersistent: true),
            outlinePreference: OutlinePreference(defaults: defaults, isPersistent: true),
            markdownSettings: MarkdownSettings(defaults: defaults, isPersistent: true), customPreprocessor: section,
            defaultViewerOffer: DefaultViewerOfferController(viewer: viewer))
        #expect(model.customPreprocessor === section)
        store.executablePath = try scripts.upcase()
        #expect(section.executablePath == store.executablePath, "follows the store")
    }
}
