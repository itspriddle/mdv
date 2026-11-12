import AppKit
import CoreServices
import PeepCore

/// Peep's parameters (`peep --theme`, `--wait`) of recent Open Documents events, by file, so
/// `DocumentController` can apply them to the files AppKit opens for each event (#67, #69).
///
/// AppKit handles Open Documents events itself (it never calls the delegate's
/// `application(_:open:)` for Peep's document types) and, while an earlier open is still in
/// flight, opens an event's files later, when `NSAppleEventManager.currentAppleEvent` is no
/// longer the event. So the parameters are taken as the event arrives (`OpenDocumentsEventTap`)
/// and looked up by file when AppKit opens it. Each file's entry is taken once; entries expire
/// after `lifetime`, so a later open of the same file (Finder) never inherits them.
///
/// Like every event parameter, these are untrusted: `AppOpenParameters(event:)` checks them,
/// and `DocumentOpener` uses a theme only if it is registered.
@MainActor
final class OpenDocumentsEventLog {
    /// How long an event's parameters wait for AppKit to open its files.
    static let lifetime: Duration = .seconds(30)
    /// The most events remembered at once; the oldest go first.
    static let maximumEntries = 32

    private struct Entry {
        var files: [URL]
        let parameters: AppOpenParameters
        let received: ContinuousClock.Instant
    }

    private var entries: [Entry] = []
    private let clock = ContinuousClock()

    /// Remembers `event`'s parameters for its files, when it is an Open Documents event with
    /// any. File items of any type are read (Launch Services sends file URLs, `open` bookmarks):
    /// they are only keys here, never opened.
    func record(_ event: NSAppleEventDescriptor) {
        guard let parameters = DocumentController.openDocumentsParameters(event) else {
            return
        }
        let files = Self.files(in: event)
        guard !files.isEmpty else {
            return
        }
        prune()
        entries.append(Entry(files: files, parameters: parameters, received: clock.now))
        if entries.count > Self.maximumEntries {
            entries.removeFirst(entries.count - Self.maximumEntries)
        }
    }

    /// The parameters of the oldest recorded event naming `url` (the same file, by
    /// `DocumentController.isSameFile`), which no longer apply to that file afterwards.
    func take(for url: URL) -> AppOpenParameters? {
        prune()
        for index in entries.indices {
            guard let fileIndex = entries[index].files.firstIndex(where: { DocumentController.isSameFile($0, url) })
            else {
                continue
            }
            let parameters = entries[index].parameters
            entries[index].files.remove(at: fileIndex)
            if entries[index].files.isEmpty {
                entries.remove(at: index)
            }
            return parameters
        }
        return nil
    }

    /// Whether nothing is waiting (tests).
    var isEmpty: Bool { entries.isEmpty }

    private func prune() {
        let now = clock.now
        entries.removeAll { now - $0.received > Self.lifetime }
    }

    /// The file URLs in an Open Documents event's direct object (a list, or one item), at most
    /// `AppOpenEvent.maximumFiles`.
    private static func files(in event: NSAppleEventDescriptor) -> [URL] {
        guard let object = event.paramDescriptor(forKeyword: keyDirectObject) else {
            return []
        }
        guard object.descriptorType == DescType(typeAEList) else {
            return object.fileURLValue.map { [$0] } ?? []
        }
        let count = min(object.numberOfItems, AppOpenEvent.maximumFiles)
        guard count > 0 else {
            return []
        }
        return (1...count).compactMap { object.atIndex($0)?.fileURLValue }
    }
}

/// Puts `OpenDocumentsEventLog` in front of AppKit's Open Documents handling: an Apple Event
/// Manager handler for `aevt/odoc` that records the event, then passes it on unchanged, to the
/// handler it replaced (`AEGetEventHandler`) or, when there was none for that exact event (the
/// Foundation handler may be installed for a wildcard), to `NSAppleEventManager`'s dispatch, which
/// is what Foundation's handler calls. AppKit handles every event exactly as before. Installed
/// once, in `applicationWillFinishLaunching` (after AppKit registers its handlers, before the
/// first event).
enum OpenDocumentsEventTap {
    private struct Installed {
        /// The handler this one replaced, with its refcon.
        let next: (handler: AEEventHandlerUPP, refcon: UnsafeMutableRawPointer)?
        weak var log: OpenDocumentsEventLog?
    }

    /// Set once on the main thread before any event is dispatched; read on the main thread.
    nonisolated(unsafe) private static var installed: Installed?

    /// The refcon when there is none to pass on (the APIs take a non-nil pointer; Foundation's
    /// dispatch doesn't read it).
    nonisolated(unsafe) private static let placeholderRefcon = UnsafeMutableRawPointer.allocate(
        byteCount: 1, alignment: 1)

    /// Whether the tap is installed (tests).
    static var isInstalled: Bool { installed != nil }

    /// Installs the tap for `log`; false when it is already installed or the Apple Event
    /// Manager refuses it.
    @MainActor
    @discardableResult
    static func install(log: OpenDocumentsEventLog) -> Bool {
        guard installed == nil else {
            return false
        }
        var handler: AEEventHandlerUPP?
        var refcon: UnsafeMutableRawPointer?
        let eventClass = AEEventClass(kCoreEventClass)
        let eventID = AEEventID(kAEOpenDocuments)
        var next: (handler: AEEventHandlerUPP, refcon: UnsafeMutableRawPointer)?
        if AEGetEventHandler(eventClass, eventID, &handler, &refcon, false) == noErr, let handler, let refcon {
            next = (handler, refcon)
        }
        installed = Installed(next: next, log: log)
        guard AEInstallEventHandler(eventClass, eventID, openDocumentsTap, refcon ?? placeholderRefcon, false) == noErr
        else {
            installed = nil
            return false
        }
        return true
    }

    /// Records `event` (on the main thread, where AppKit dispatches Apple Events) and passes
    /// it on.
    fileprivate static func handle(
        _ event: UnsafePointer<AppleEvent>, reply: UnsafeMutablePointer<AppleEvent>,
        refcon: UnsafeMutableRawPointer?
    ) -> OSErr {
        guard let installed else {
            return OSErr(errAEEventNotHandled)
        }
        var copy = AEDesc()
        if Thread.isMainThread, AEDuplicateDesc(event, &copy) == noErr {
            // Made and used here, on the main thread, before the handler returns.
            nonisolated(unsafe) let descriptor = NSAppleEventDescriptor(aeDescNoCopy: &copy)
            nonisolated(unsafe) let log = installed.log
            MainActor.assumeIsolated {
                log?.record(descriptor)
            }
        }
        if let next = installed.next {
            return next.handler(event, reply, next.refcon)
        }
        return NSAppleEventManager.shared().dispatchRawAppleEvent(
            event, withRawReply: reply, handlerRefCon: refcon ?? placeholderRefcon)
    }
}

/// The installed handler.
private func openDocumentsTap(
    _ event: UnsafePointer<AppleEvent>?, _ reply: UnsafeMutablePointer<AppleEvent>?, _ refcon: UnsafeMutableRawPointer?
) -> OSErr {
    guard let event, let reply else {
        return OSErr(errAEEventNotHandled)
    }
    return OpenDocumentsEventTap.handle(event, reply: reply, refcon: refcon)
}
