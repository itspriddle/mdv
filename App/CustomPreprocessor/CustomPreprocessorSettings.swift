import Foundation
import PeepCore

/// The custom preprocessor a render runs (#57): the executable and its arguments as Settings
/// stores them, before validation. Part of `MarkdownPreferences`, so turning the preprocessor
/// on or off, or changing its executable or arguments, re-renders open documents like any other
/// Settings > Markdown change.
///
/// It is validated when a render builds its `PreprocessorConfiguration`, and the runner checks
/// the executable again just before it starts; an executable that went away is a failure the
/// window shows, never a silent unprocessed render.
struct CustomPreprocessorPreference: Equatable, Sendable {
    /// An absolute path, as the Open panel returned it.
    var executablePath: String
    var arguments: [String] = []
}

/// The most recent custom preprocessor run in this session, for Settings' last-run line (#57).
/// Kept in memory only.
struct CustomPreprocessorRun: Equatable, Sendable {
    /// The file name of the document it ran on.
    var documentName: String
    var date: Date
    /// Why it failed; `nil` when it succeeded.
    var error: PreprocessorError?
}

/// The reader's custom preprocessor (#57, Settings > Markdown > Custom preprocessor), persisted
/// in `UserDefaults`: whether it is on, the executable, and its arguments.
///
/// It is off by default. Settings turns it on only after a warning (`CustomPreprocessorModel`),
/// and nothing else turns it on: documents can't (frontmatter overrides never reach it, #54),
/// and there is no launch argument for it outside Debug UI tests (`UITestHooks`). The
/// executable is only ever set from an Open panel, so it is a file the reader picked.
///
/// Stored values are untrusted input: a path that isn't absolute reads as no executable, and
/// the preprocessor is on only with an executable (`preference`).
@MainActor
final class CustomPreprocessorSettings {
    /// The app's settings. UI tests and hosted unit tests keep them in memory, starting off
    /// (or, in a Debug UI test, at `-PeepUITestPreprocessor`'s executable), so neither reads nor
    /// writes the reader's preprocessor.
    static let shared: CustomPreprocessorSettings = {
        let settings = CustomPreprocessorSettings(
            isPersistent: !UITestHooks.isUITesting && !AppDelegate.isHostingUnitTests)
        if let executable = UITestHooks.preprocessorExecutable {
            settings.executablePath = executable
            settings.isEnabled = true
        }
        return settings
    }()

    /// Posted (object: the settings) after any setting changes. Open documents render again.
    static let didChangeNotification = Notification.Name("PeepCustomPreprocessorSettingsDidChange")
    /// Posted (object: the settings) after a run is recorded (`lastRun`). Only Settings follows
    /// it: a document finishing its run must not make other documents render again.
    static let lastRunDidChangeNotification = Notification.Name("PeepCustomPreprocessorLastRunDidChange")

    /// `UserDefaults` keys. Each is absent at its default.
    static let enabledKey = "CustomPreprocessorEnabled"
    static let executableKey = "CustomPreprocessorExecutable"
    static let argumentsKey = "CustomPreprocessorArguments"

    private let defaults: UserDefaults
    private let isPersistent: Bool
    private var memoryEnabled = false
    private var memoryExecutable: String?
    private var memoryArguments: [String] = []

    /// The last run in this session (never persisted).
    private(set) var lastRun: CustomPreprocessorRun?

    init(defaults: UserDefaults = .standard, isPersistent: Bool = !UITestHooks.isUITesting) {
        self.defaults = defaults
        self.isPersistent = isPersistent
    }

    /// What renders run: `nil` unless the preprocessor is on and has an executable.
    var preference: CustomPreprocessorPreference? {
        guard isEnabled, let executablePath else {
            return nil
        }
        return CustomPreprocessorPreference(executablePath: executablePath, arguments: arguments)
    }

    /// Whether the preprocessor is on. Reads `false` without an executable. Only Settings, after
    /// its warning, sets it.
    var isEnabled: Bool {
        get {
            guard executablePath != nil else {
                return false
            }
            return isPersistent ? defaults.bool(forKey: Self.enabledKey) : memoryEnabled
        }
        set {
            let enabled = newValue && executablePath != nil
            guard enabled != isEnabled else {
                return
            }
            if isPersistent {
                if enabled {
                    defaults.set(true, forKey: Self.enabledKey)
                } else {
                    defaults.removeObject(forKey: Self.enabledKey)
                }
            } else {
                memoryEnabled = enabled
            }
            didChange()
        }
    }

    /// The executable's absolute path, or `nil`. Setting a path that isn't absolute is ignored.
    var executablePath: String? {
        get {
            let path = isPersistent ? defaults.string(forKey: Self.executableKey) : memoryExecutable
            return path.flatMap(Self.absolutePath)
        }
        set {
            guard newValue == nil || newValue.flatMap(Self.absolutePath) != nil, newValue != executablePath else {
                return
            }
            if isPersistent {
                if let newValue {
                    defaults.set(newValue, forKey: Self.executableKey)
                } else {
                    defaults.removeObject(forKey: Self.executableKey)
                }
            } else {
                memoryExecutable = newValue
            }
            didChange()
        }
    }

    /// The arguments passed after the executable, verbatim.
    var arguments: [String] {
        get {
            isPersistent ? defaults.stringArray(forKey: Self.argumentsKey) ?? [] : memoryArguments
        }
        set {
            guard newValue != arguments else {
                return
            }
            if isPersistent {
                if newValue.isEmpty {
                    defaults.removeObject(forKey: Self.argumentsKey)
                } else {
                    defaults.set(newValue, forKey: Self.argumentsKey)
                }
            } else {
                memoryArguments = newValue
            }
            didChange()
        }
    }

    /// Turns the preprocessor off and forgets the executable and arguments.
    func reset() {
        guard isEnabled || executablePath != nil || !arguments.isEmpty else {
            return
        }
        if isPersistent {
            for key in [Self.enabledKey, Self.executableKey, Self.argumentsKey] {
                defaults.removeObject(forKey: key)
            }
        } else {
            memoryEnabled = false
            memoryExecutable = nil
            memoryArguments = []
        }
        didChange()
    }

    /// Records a finished run (`MarkdownDocument.setContent(_:)`), for Settings' last-run line.
    func recordRun(_ run: CustomPreprocessorRun) {
        lastRun = run
        NotificationCenter.default.post(name: Self.lastRunDidChangeNotification, object: self)
    }

    /// `path` if it is absolute and has no NUL character.
    private static func absolutePath(_ path: String) -> String? {
        path.hasPrefix("/") && !path.utf8.contains(0) ? path : nil
    }

    private func didChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
