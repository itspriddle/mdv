import Dispatch
import notify

/// A registration for a Darwin notification (`notify(3)`), delivered on a dispatch queue (no run
/// loop needed). `WindowsClosedWaiter` uses it for the app's "windows closed" notification.
///
/// (Its own file: SwiftLint and swift-format sort `notify` differently next to capitalized
/// module names.)
struct DarwinNotificationRegistration: Sendable {
    private let token: Int32

    /// Registers `handler` for `name`, or the status `notify_register_dispatch` failed with.
    static func register(
        _ name: String, queue: DispatchQueue, handler: @escaping @Sendable () -> Void
    ) -> Result<Self, NotifyFailure> {
        var token: Int32 = 0
        let status = notify_register_dispatch(name, &token, queue) { _ in handler() }
        guard status == NOTIFY_STATUS_OK else {
            return .failure(NotifyFailure(status: status))
        }
        return .success(Self(token: token))
    }

    /// Ends the registration.
    func cancel() {
        notify_cancel(token)
    }

    /// Posts `name` (tests stand in for the app).
    static func post(_ name: String) {
        notify_post(name)
    }

    struct NotifyFailure: Error {
        var status: UInt32
    }
}
