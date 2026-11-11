import CoreServices
import Foundation
import MdvCore
import Testing

/// `mdv FILE`'s Open Documents event (#67): what the CLI builds, and how the app reads it as
/// untrusted input.
@Suite("App open event")
struct AppOpenEventTests {
    static var target: NSAppleEventDescriptor { NSAppleEventDescriptor(bundleIdentifier: "com.itspriddle.mdv") }

    static func openDocuments() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenDocuments),
            targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
    }

    @Test("the event is Open Documents with the files in order and the theme")
    func roundTrip() throws {
        let files = [URL(filePath: "/tmp/a b.md"), URL(filePath: "/tmp/ü.md")]
        let event = AppOpenEvent.make(
            files: files, parameters: AppOpenParameters(themeID: "serif"), target: Self.target)
        #expect(AppOpenEvent.isOpenDocuments(event))
        let list = try #require(event.paramDescriptor(forKeyword: keyDirectObject))
        #expect(list.numberOfItems == 2)
        #expect((1...list.numberOfItems).compactMap { list.atIndex($0)?.fileURLValue } == files)
        #expect(AppOpenParameters(event: event) == AppOpenParameters(themeID: "serif"))
    }

    @Test("without options, the event has no mdv parameters (as Finder's)")
    func noOptions() {
        let event = AppOpenEvent.make(files: [], parameters: AppOpenParameters(), target: Self.target)
        #expect(event.paramDescriptor(forKeyword: AppOpenEvent.themeKeyword) == nil)
        #expect(AppOpenParameters(event: event) == AppOpenParameters())
        #expect(AppOpenParameters(event: nil) == AppOpenParameters())
    }

    @Test("a theme in UTF-8 text is read too")
    func utf8Theme() throws {
        let event = Self.openDocuments()
        let text = try #require(NSAppleEventDescriptor(descriptorType: typeUTF8Text, data: Data("document".utf8)))
        event.setParam(text, forKeyword: AppOpenEvent.themeKeyword)
        #expect(AppOpenParameters(event: event).themeID == "document")
    }

    @Test(
        "hostile theme values are dropped",
        arguments: [
            "", " serif", "serif\n", "a\u{0}b", "a\u{202E}b", String(repeating: "x", count: 257),
            String(repeating: "é", count: 300),
        ])
    func hostileThemeStrings(value: String) {
        let event = Self.openDocuments()
        event.setParam(NSAppleEventDescriptor(string: value), forKeyword: AppOpenEvent.themeKeyword)
        #expect(AppOpenParameters(event: event).themeID == nil)
    }

    @Test("a theme of the wrong type, or oversized data, is dropped")
    func hostileThemeTypes() throws {
        let numbers = Self.openDocuments()
        numbers.setParam(NSAppleEventDescriptor(int32: 7), forKeyword: AppOpenEvent.themeKeyword)
        #expect(AppOpenParameters(event: numbers).themeID == nil)

        let data = Self.openDocuments()
        let bytes = try #require(NSAppleEventDescriptor(descriptorType: typeData, data: Data("serif".utf8)))
        data.setParam(bytes, forKeyword: AppOpenEvent.themeKeyword)
        #expect(AppOpenParameters(event: data).themeID == nil)

        let huge = Self.openDocuments()
        let big = try #require(
            NSAppleEventDescriptor(descriptorType: typeUTF8Text, data: Data(repeating: 0x61, count: 10_000_000)))
        huge.setParam(big, forKeyword: AppOpenEvent.themeKeyword)
        #expect(AppOpenParameters(event: huge).themeID == nil)

        let list = Self.openDocuments()
        list.setParam(NSAppleEventDescriptor.list(), forKeyword: AppOpenEvent.themeKeyword)
        #expect(AppOpenParameters(event: list).themeID == nil)
    }

    @Test("parameters on any other event are ignored")
    func otherEvent() {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: Self.target, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: "serif"), forKeyword: AppOpenEvent.themeKeyword)
        #expect(AppOpenParameters(event: event) == AppOpenParameters())
    }

    @Test("plausible theme ids")
    func plausible() {
        #expect(AppOpenParameters.isPlausibleThemeID("github"))
        #expect(AppOpenParameters.isPlausibleThemeID("custom:My Theme.css"))
        #expect(AppOpenParameters.isPlausibleThemeID(String(repeating: "x", count: 256)))
        #expect(!AppOpenParameters.isPlausibleThemeID(String(repeating: "x", count: 257)))
    }
}
