import Foundation
import UniformTypeIdentifiers

/// Reads and changes whether mdv is the default viewer for Markdown, and decides when to offer.
///
/// Offer rules (#23): the offer appears when a document window opens while another app is the
/// default, at most once per launch. "Don't Ask Again" ends it for good, "Not Now" snoozes it for
/// `snoozeInterval`, and "Make Default" (or becoming the default any other way) ends it while mdv
/// stays the default. UI tests never see it (`UITestHooks.suppressesFirstRunPrompts`).
@MainActor
final class DefaultViewer {
    /// The user's answer to the offer.
    enum Choice: Equatable {
        case makeDefault
        case notNow
        case dontAskAgain
    }

    enum Failure: Error, Equatable {
        /// mdv has no bundle identifier (not running from an app bundle).
        case noBundleIdentifier
        /// Launch Services accepted the change but still reports another default.
        case notApplied
    }

    /// The Markdown types mdv declares as a handler (`LSHandlerRank` other than `None`).
    static let contentTypes: [UTType] = [UTType(importedAs: "net.daringfireball.markdown")]

    /// How long "Not Now" postpones the offer.
    static let snoozeInterval: TimeInterval = 30 * 24 * 60 * 60

    static let declinedKey = "DefaultViewerOfferDeclined"
    static let lastOfferedKey = "DefaultViewerOfferLastOffered"

    private let workspace: any DefaultApplicationWorkspace
    private let defaults: UserDefaults
    private let applicationURL: URL
    private let bundleIdentifier: String?
    private let isSuppressed: Bool
    private let now: () -> Date
    private var offeredThisLaunch = false

    init(
        workspace: any DefaultApplicationWorkspace = SystemDefaultApplicationWorkspace(),
        defaults: UserDefaults = .standard,
        applicationURL: URL = Bundle.main.bundleURL,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        isSuppressed: Bool = UITestHooks.suppressesFirstRunPrompts,
        now: @escaping () -> Date = Date.init
    ) {
        self.workspace = workspace
        self.defaults = defaults
        self.applicationURL = applicationURL
        self.bundleIdentifier = bundleIdentifier
        self.isSuppressed = isSuppressed
        self.now = now
    }

    /// Whether mdv opens every declared Markdown type by default.
    var isDefault: Bool {
        guard let bundleIdentifier else {
            return false
        }
        return Self.contentTypes.allSatisfy {
            workspace.defaultApplicationBundleIdentifier(toOpen: $0)?.caseInsensitiveCompare(bundleIdentifier)
                == .orderedSame
        }
    }

    /// Whether to show the offer now. Call when a document window opens.
    var shouldOffer: Bool {
        guard !isSuppressed, !offeredThisLaunch, !defaults.bool(forKey: Self.declinedKey) else {
            return false
        }
        if let last = defaults.object(forKey: Self.lastOfferedKey) as? Date,
            now().timeIntervalSince(last) < Self.snoozeInterval
        {
            return false
        }
        return !isDefault
    }

    /// Records that the offer is on screen, so it shows at most once per launch.
    func offerShown() {
        offeredThisLaunch = true
        defaults.set(now(), forKey: Self.lastOfferedKey)
    }

    /// Records the user's answer and, for `.makeDefault`, makes mdv the default.
    func respond(_ choice: Choice) async throws {
        switch choice {
        case .makeDefault:
            try await makeDefault()
        case .notNow:
            break  // `offerShown()` already started the snooze.
        case .dontAskAgain:
            defaults.set(true, forKey: Self.declinedKey)
        }
    }

    /// Makes mdv the default for every declared Markdown type, then confirms it took effect.
    func makeDefault() async throws {
        guard bundleIdentifier != nil else {
            throw Failure.noBundleIdentifier
        }
        for contentType in Self.contentTypes {
            try await workspace.setDefaultApplication(at: applicationURL, toOpen: contentType)
        }
        guard isDefault else {
            throw Failure.notApplied
        }
    }
}
