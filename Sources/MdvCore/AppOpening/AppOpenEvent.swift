import CoreServices
import Foundation

/// The Apple Event `mdv FILE` sends the app (#67): a standard Open Documents event
/// (`aevt/odoc`, the event Finder sends), its direct object the files, plus mdv's own optional
/// parameters (`AppOpenParameters`). The CLI hands it to Launch Services
/// (`NSWorkspace.OpenConfiguration.appleEvent`), which launches the app with it or sends it to
/// the running app, so the app opens files exactly as it does from Finder.
///
/// Trust model: any local process can send the app an Open Documents event, with any parameters.
/// The parameters are presentation-only (they can't widen what a document may do), and the app
/// reads them as untrusted input (`AppOpenParameters(event:)`): wrong types, oversized values,
/// and unknown keywords are ignored. Nothing here is reachable from a web page (no URL scheme).
public enum AppOpenEvent {
    /// `mdvT`: the theme id for the opened windows (UTF-8 or UTF-16 text).
    public static let themeKeyword: AEKeyword = 0x6D64_7654
    // Reserved for later M5 issues (see docs/VISION.md, "CLI to app"):
    // `mdvI` (0x6D64_7649) standard input for #68, `mdvW` (0x6D64_7657) the --wait token for #69.

    /// The longest parameter value the app decodes, in bytes. A theme id is at most 256
    /// characters (`AppOpenParameters.maximumThemeIDLength`); 4 bytes each covers any encoding.
    public static let maximumTextBytes = 1024

    /// The Open Documents event for `files` with `parameters`, addressed to `target`: the app's
    /// bundle id for Launch Services (which delivers it to the app it launches or finds), or a
    /// process id to send it directly.
    public static func make(
        files: [URL], parameters: AppOpenParameters, target: NSAppleEventDescriptor
    ) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenDocuments),
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
        return event
    }

    /// Whether `event` is an Open Documents event.
    public static func isOpenDocuments(_ event: NSAppleEventDescriptor) -> Bool {
        event.eventClass == AEEventClass(kCoreEventClass) && event.eventID == AEEventID(kAEOpenDocuments)
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

    public init(themeID: String? = nil) {
        self.themeID = themeID
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
        self.init(themeID: themeID.flatMap { Self.isPlausibleThemeID($0) ? $0 : nil })
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
