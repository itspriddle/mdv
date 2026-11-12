import CoreServices
import Foundation

// `mdv --wait` (#69): the CLI puts a random token on its open event (`mdvW`); the app remembers
// which windows the event opened or brought forward, and when the last of them closes (or the
// app quits) it posts a Darwin notification (`notify(3)`) named for the token. The CLI waits
// for that notification or for the app's process to exit, whichever comes first.
//
// Trust model: any local process can post any Darwin notification, and send the app an open
// event with any token. A forged notification can only end a wait early (the CLI exits 0 and
// the windows stay open); a forged token only makes the app post a notification under its own
// prefix when windows close. Neither acts in the app. The token is a random (version 4) UUID
// per invocation, so another process can't name a wait it didn't start, and the app accepts
// only a well-formed UUID, so the name it posts is always the prefix plus 36 characters.

extension AppOpenEvent {
    /// `mdvW`: the `--wait` token, a UUID string (UTF-8 or UTF-16 text).
    public static let waitKeyword: AEKeyword = 0x6D64_7657

    /// The prefix of every "windows closed" notification name.
    public static let windowsClosedNotificationPrefix = "com.itspriddle.mdv.windowsClosed."

    /// The Darwin notification the app posts when the windows of the open event carrying `token`
    /// have all closed, or the app is quitting.
    public static func windowsClosedNotificationName(for token: UUID) -> String {
        windowsClosedNotificationPrefix + token.uuidString
    }

    /// Adds `token` to `event` as `mdvW`; nothing when it is nil.
    static func setWaitToken(_ token: UUID?, on event: NSAppleEventDescriptor) {
        guard let token else {
            return
        }
        event.setParam(NSAppleEventDescriptor(string: token.uuidString), forKeyword: waitKeyword)
    }

    /// The `mdvW` token in `event`: text that is exactly a UUID string (36 characters); nil for
    /// anything else.
    static func waitToken(in event: NSAppleEventDescriptor) -> UUID? {
        guard let text = text(event.paramDescriptor(forKeyword: waitKeyword)), text.utf8.count == 36 else {
            return nil
        }
        return UUID(uuidString: text)
    }
}
