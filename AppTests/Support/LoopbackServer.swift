import Foundation
import Network

/// A TCP server on 127.0.0.1 (never another interface) that records every connection made to
/// it, so tests can prove what a page did or didn't fetch without touching the network.
///
/// Plain HTTP requests get a 1x1 PNG; anything else (a TLS ClientHello, for `https:` URLs
/// pointed here) is recorded and closed, so an `https:` load shows up as an attempted
/// connection whose first byte is `0x16`.
final class LoopbackServer: @unchecked Sendable {
    /// What one connection sent first.
    struct Connection: Sendable {
        let firstBytes: Data

        /// A TLS handshake (a browser loading an `https:` URL).
        var isTLS: Bool { firstBytes.first == 0x16 }

        /// `GET /path HTTP/1.1` for plain HTTP, else nil.
        var requestLine: String? {
            guard !isTLS, let text = String(bytes: firstBytes, encoding: .utf8) else {
                return nil
            }
            return text.split(separator: "\r\n", maxSplits: 1).first.map(String.init)
        }
    }

    enum StartError: Error {
        case failed(String)
    }

    let port: UInt16
    private let listener: NWListener
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var acceptedCount = 0
    private var recorded: [Connection] = []

    /// Every connection accepted so far, including ones that sent nothing yet.
    var connectionCount: Int { lock.withLock { acceptedCount } }
    var connections: [Connection] { lock.withLock { recorded } }

    private init(listener: NWListener, port: UInt16, queue: DispatchQueue) {
        self.listener = listener
        self.port = port
        self.queue = queue
    }

    /// Starts listening on 127.0.0.1 at a free port.
    static func start() async throws -> LoopbackServer {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.acceptLocalOnly = true
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "LoopbackServer")
        let box = ServerBox()
        listener.newConnectionHandler = { connection in
            box.server?.accept(connection)
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = OnceFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() {
                        continuation.resume(returning: listener.port?.rawValue ?? 0)
                    }
                case .failed(let error):
                    if once.claim() {
                        continuation.resume(throwing: StartError.failed("\(error)"))
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        let server = LoopbackServer(listener: listener, port: port, queue: queue)
        box.server = server
        return server
    }

    /// `http://127.0.0.1:<port><path>`, or `https:` for the TLS-attempt case.
    func url(_ path: String, https: Bool = false) -> String {
        "\(https ? "https" : "http")://127.0.0.1:\(port)\(path)"
    }

    func stop() {
        listener.cancel()
    }

    private func accept(_ connection: NWConnection) {
        lock.withLock { acceptedCount += 1 }
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            let record = Connection(firstBytes: data ?? Data())
            self?.lock.withLock { self?.recorded.append(record) }
            guard record.requestLine != nil else {
                connection.cancel()
                return
            }
            connection.send(
                content: Self.pngResponse, contentContext: .finalMessage, isComplete: true,
                completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// A 1x1 PNG over HTTP/1.1, then close.
    private static let pngResponse: Data = {
        let png =
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=")
            ?? Data()
        let header =
            "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(png.count)\r\n"
            + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(header.utf8) + png
    }()
}

/// Lets the listener's handler reach the server created after the listener starts.
private final class ServerBox: @unchecked Sendable {
    private let lock = NSLock()
    private weak var stored: LoopbackServer?

    var server: LoopbackServer? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Resumes a continuation once.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}
