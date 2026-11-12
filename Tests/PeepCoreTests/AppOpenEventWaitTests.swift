import CoreServices
import Foundation
import PeepCore
import Testing

/// `peep --wait`'s token on the open event (#69), read by the app as untrusted input.
@Suite("App open event: wait token")
struct AppOpenEventWaitTests {
    @Test("the token round-trips, on both kinds of event, next to the theme")
    func roundTrip() {
        let token = UUID()
        let parameters = AppOpenParameters(themeID: "serif", waitToken: token)
        for kind in [AppOpenEvent.Kind.openDocuments, .direct] {
            let event = AppOpenEvent.make(
                files: [URL(filePath: "/tmp/a.md")], parameters: parameters, target: AppOpenEventTests.target,
                kind: kind)
            #expect(AppOpenParameters(event: event) == parameters)
        }
    }

    @Test("without --wait the event has no token")
    func noToken() {
        let event = AppOpenEvent.make(files: [], parameters: AppOpenParameters(), target: AppOpenEventTests.target)
        #expect(event.paramDescriptor(forKeyword: AppOpenEvent.waitKeyword) == nil)
        #expect(AppOpenParameters(event: event).waitToken == nil)
    }

    @Test("a lowercase UUID in UTF-8 text is read too")
    func lowercase() throws {
        let token = UUID()
        let event = AppOpenEventTests.openDocuments()
        let text = try #require(
            NSAppleEventDescriptor(descriptorType: typeUTF8Text, data: Data(token.uuidString.lowercased().utf8)))
        event.setParam(text, forKeyword: AppOpenEvent.waitKeyword)
        #expect(AppOpenParameters(event: event).waitToken == token)
    }

    @Test(
        "anything but a UUID string is dropped",
        arguments: [
            "", "token", " \(UUID().uuidString)", "\(UUID().uuidString)\n", "\(UUID().uuidString)x",
            "\(UUID().uuidString)\u{0}", "../../etc", String(repeating: "A", count: 2000),
            UUID().uuidString.replacingOccurrences(of: "-", with: ""),
        ])
    func hostileStrings(value: String) {
        let event = AppOpenEventTests.openDocuments()
        event.setParam(NSAppleEventDescriptor(string: value), forKeyword: AppOpenEvent.waitKeyword)
        #expect(AppOpenParameters(event: event).waitToken == nil)
    }

    @Test("a token of the wrong type is dropped")
    func hostileTypes() throws {
        let number = AppOpenEventTests.openDocuments()
        number.setParam(NSAppleEventDescriptor(int32: 7), forKeyword: AppOpenEvent.waitKeyword)
        #expect(AppOpenParameters(event: number).waitToken == nil)

        let data = AppOpenEventTests.openDocuments()
        let bytes = try #require(
            NSAppleEventDescriptor(descriptorType: typeData, data: Data(UUID().uuidString.utf8)))
        data.setParam(bytes, forKeyword: AppOpenEvent.waitKeyword)
        #expect(AppOpenParameters(event: data).waitToken == nil)
    }

    @Test("the notification name is the prefix and the canonical token")
    func notificationName() throws {
        let token = try #require(UUID(uuidString: "e621e1f8-c36c-495a-93fc-0c247a3e6e5f"))
        #expect(
            AppOpenEvent.windowsClosedNotificationName(for: token)
                == "now.peep.Peep.windowsClosed.E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
    }
}
