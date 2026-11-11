import CoreServices
import Foundation

/// The Apple Event `mdv FILE` sends the app (#67): a standard Open Documents event
/// (`aevt/odoc`, the event Finder sends), its direct object the files, plus mdv's own optional
/// parameters (`AppOpenParameters`). The CLI hands it to Launch Services
/// (`NSWorkspace.OpenConfiguration.appleEvent`), which launches the app with it or sends it to
/// the running app, so the app opens files exactly as it does from Finder.
///
/// When the CLI must reach a running copy without Launch Services (`Kind.direct`: another copy
/// with the same bundle id is running, or the caller is sandboxed), it sends the same content as
/// mdv's own event class instead (`mdv `/`odoc`), which the app handles with the same code.
/// AppKit answers an Open Documents event that didn't come through Launch Services as a
/// scripting command, which never reaches the app delegate and would drop the parameters.
///
/// Trust model: any local process can send the app either event, with any parameters. The
/// parameters are presentation-only (they can't widen what a document may do), and the app
/// reads them as untrusted input (`AppOpenParameters(event:)`): wrong types, oversized values,
/// and unknown keywords are ignored. Nothing here is reachable from a web page (no URL scheme).
public enum AppOpenEvent {
    /// Which event carries the open.
    public enum Kind: Sendable {
        /// `aevt/odoc`, through Launch Services.
        case openDocuments
        /// `mdv /odoc`, sent straight to a running app.
        case direct
    }

    /// `mdv `: the event class of `Kind.direct`.
    public static let directEventClass: AEEventClass = 0x6D64_7620
    /// `odoc`: the event id of `Kind.direct`.
    public static let directEventID = AEEventID(kAEOpenDocuments)
    /// `mdvT`: the theme id for the opened windows (UTF-8 or UTF-16 text).
    public static let themeKeyword: AEKeyword = 0x6D64_7654
    // `mdvW` (#69) is `waitKeyword`. `mdvI` (0x6D64_7649) was reserved for standard input;
    // #68 needed no parameter (`StandardInputHandoff`), so it stays unused.

    /// The longest parameter value the app decodes, in bytes. A theme id is at most 256
    /// characters (`AppOpenParameters.maximumThemeIDLength`); 4 bytes each covers any encoding.
    public static let maximumTextBytes = 1024
    /// The most files one direct event opens; the rest are ignored.
    public static let maximumFiles = 1000

    /// The event for `files` with `parameters`, addressed to `target`: the app's bundle id for
    /// Launch Services (which delivers it to the app it launches or finds), or a process id to
    /// send it directly (`kind: .direct`).
    public static func make(
        files: [URL], parameters: AppOpenParameters, target: NSAppleEventDescriptor, kind: Kind = .openDocuments
    ) -> NSAppleEventDescriptor {
        let eventClass = kind == .direct ? directEventClass : AEEventClass(kCoreEventClass)
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: eventClass, eventID: AEEventID(kAEOpenDocuments),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        let list = NSAppleEventDescriptor.list()
        for file in files {
            list.insert(NSAppleEventDescriptor(fileURL: file), at: list.numberOfItems + 1)
        }
        event.setParam(list, forKeyword: keyDirectObject)
        if let themeID = parameters.themeID {
            event.setParam(NSAppleEventDescriptor(string: themeID), forKeyword: themeKeyword)
        }
        setWaitToken(parameters.waitToken, on: event)
        return event
    }

    /// Whether `event` is an Open Documents event, or mdv's direct one.
    public static func isOpenDocuments(_ event: NSAppleEventDescriptor) -> Bool {
        (event.eventClass == AEEventClass(kCoreEventClass) || event.eventClass == directEventClass)
            && event.eventID == AEEventID(kAEOpenDocuments)
    }

    /// The file URLs in a direct event's direct object (a list, or one file), in order: items
    /// that aren't file URLs are skipped, and at most `maximumFiles` are read. Empty for
    /// anything else. (AppKit reads Open Documents events' files itself.)
    public static func files(in event: NSAppleEventDescriptor) -> [URL] {
        guard event.eventClass == directEventClass, event.eventID == directEventID,
            let object = event.paramDescriptor(forKeyword: keyDirectObject)
        else {
            return []
        }
        guard object.descriptorType == DescType(typeAEList) else {
            return fileURL(object).map { [$0] } ?? []
        }
        let count = min(object.numberOfItems, maximumFiles)
        guard count > 0 else {
            return []
        }
        return (1...count).compactMap { fileURL(object.atIndex($0)) }
    }

    /// A `typeFileURL` descriptor's file URL; nil for any other type (text is never coerced
    /// into a path).
    private static func fileURL(_ descriptor: NSAppleEventDescriptor?) -> URL? {
        guard let descriptor, descriptor.descriptorType == DescType(typeFileURL),
            let url = descriptor.fileURLValue, url.isFileURL
        else {
            return nil
        }
        return url
    }

    /// The text in `descriptor`, when it is UTF-8 or UTF-16 text of at most
    /// `maximumTextBytes` bytes; nil for anything else.
    static func text(_ descriptor: NSAppleEventDescriptor?) -> String? {
        guard let descriptor,
            [DescType(typeUTF8Text), DescType(typeUnicodeText)].contains(descriptor.descriptorType),
            descriptor.data.count <= maximumTextBytes
        else {
            return nil
        }
        return descriptor.stringValue
    }
}

/// mdv's options for the windows an Open Documents event opens (`AppOpenEvent`). Each is
/// optional: Finder's events have none, and the app then opens files as it always has.
public struct AppOpenParameters: Equatable, Sendable {
    /// The longest theme id accepted, in characters (as restorable state's limit).
    public static let maximumThemeIDLength = 256

    /// The theme the windows show, as their View > Theme pick (`mdv --theme`). The app checks
    /// it against its registry; this type only checks it is a plausible id.
    public var themeID: String?
    /// `mdv --wait` (#69): the invocation's token. The app posts
    /// `AppOpenEvent.windowsClosedNotificationName(for:)` once every window this event opened
    /// (or brought forward) has closed.
    public var waitToken: UUID?

    public init(themeID: String? = nil, waitToken: UUID? = nil) {
        self.themeID = themeID
        self.waitToken = waitToken
    }

    /// The parameters in `event`, which may come from any local process: values of the wrong
    /// type or size are dropped, and so are theme ids that aren't plausible
    /// (`isPlausibleThemeID`). Empty for anything but an Open Documents event.
    public init(event: NSAppleEventDescriptor?) {
        guard let event, AppOpenEvent.isOpenDocuments(event) else {
            self.init()
            return
        }
        let themeID = AppOpenEvent.text(event.paramDescriptor(forKeyword: AppOpenEvent.themeKeyword))
        self.init(
            themeID: themeID.flatMap { Self.isPlausibleThemeID($0) ? $0 : nil },
            waitToken: AppOpenEvent.waitToken(in: event))
    }

    /// Whether `id` could be a theme id: 1 to 256 characters, none of them control, format
    /// (bidi overrides), or line separator characters, and no surrounding whitespace.
    public static func isPlausibleThemeID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= maximumThemeIDLength,
            id.trimmingCharacters(in: .whitespacesAndNewlines) == id
        else {
            return false
        }
        return id.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .unassigned, .privateUse:
                false
            default:
                true
            }
        }
    }
}
