import Darwin
import Foundation
import os
import XPC

/// Why a request to the recognizer did not come back with a layout.
enum RecognitionTransportError: Error, CustomStringConvertible {
    /// Vision itself failed in the service (in practice `e5rtError … 13`: its compiled
    /// model was purged while loaded). A fresh service process recovers.
    case vision(String)
    /// The service crashed, was killed, or could not be reached.
    case connection(String)
    /// No answer within the deadline: the service is stuck.
    case timedOut
    /// The reply or the image could not be encoded or decoded.
    case malformed(String)

    /// Worth one more attempt on a fresh service process.
    var isRetryable: Bool {
        switch self {
        case .vision, .connection: true
        case .timedOut, .malformed: false
        }
    }

    var description: String {
        switch self {
        case .vision(let message): "vision(\(message))"
        case .connection(let message): "connection(\(message))"
        case .timedOut: "timedOut"
        case .malformed(let message): "malformed(\(message))"
        }
    }
}

/// How `OCRService` and `VisionCacheMonitor` reach Vision. The real one is the XPC
/// service; tests use stubs to drive the retry logic.
@MainActor protocol RecognitionTransport: AnyObject {
    func recognize(_ image: ImagePayload, timeout: Duration) async throws -> RecognizedLayout
    /// Runs one small recognition at low priority so the models are loaded (or rebuilt).
    func prewarm(timeout: Duration) async throws
    /// Ends the current service process, whatever it is doing, so the next request gets a
    /// new one. Requests still in flight fail with `.connection`. For when the process is
    /// known to be stale (its models were purged) without having failed yet.
    func restart(reason: String) async
    /// Ends the service process only if a request to it failed: when several requests fail
    /// together, the first caller restarts it and the others reuse the fresh process instead
    /// of killing it in turn.
    func restartIfFailed(reason: String) async
}

/// Client side of the `OCRSelectionRecognizer` XPC service.
///
/// Uses the C XPC API rather than `XPCSession` because restarting needs the service's pid:
/// a new connection to a live service process lands in that same process, so a broken
/// Vision would survive a mere reconnect. `restart` asks the process to exit, makes sure it
/// is gone (SIGKILL as a fallback — it is our own service, same user), and only then lets
/// the next request connect, which makes launchd start a fresh one. Requests made while a
/// restart is under way wait for it.
@MainActor
final class RecognizerConnection: RecognitionTransport {
    static let shared = RecognizerConnection(
        serviceName: RecognizerProtocol.serviceName(forAppBundleID: Bundle.main.bundleIdentifier ?? "com.leodurand.ocr-selection")
    )

    let serviceName: String
    private var connection: xpc_connection_t?
    /// Whether a request on `connection` failed (Vision error, crash or timeout).
    private var connectionFailed = false
    private var restarting: Task<Void, Never>?
    private let queue = DispatchQueue(label: "com.leodurand.ocr-selection.recognizer-client", qos: .userInitiated)

    init(serviceName: String) {
        self.serviceName = serviceName
    }

    func recognize(_ image: ImagePayload, timeout: Duration) async throws -> RecognizedLayout {
        let message = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(message, RecognizerProtocol.Key.op, RecognizerProtocol.Op.recognize)
        xpc_dictionary_set_int64(message, RecognizerProtocol.Key.width, Int64(image.width))
        xpc_dictionary_set_int64(message, RecognizerProtocol.Key.height, Int64(image.height))
        xpc_dictionary_set_int64(message, RecognizerProtocol.Key.bytesPerRow, Int64(image.bytesPerRow))
        image.pixels.withUnsafeBytes { buffer in
            xpc_dictionary_set_data(message, RecognizerProtocol.Key.pixels, buffer.baseAddress!, buffer.count)
        }
        return try await perform(message, timeout: timeout)
    }

    func prewarm(timeout: Duration) async throws {
        let message = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(message, RecognizerProtocol.Key.op, RecognizerProtocol.Op.prewarm)
        _ = try await perform(message, timeout: timeout)
    }

    func restart(reason: String) async {
        if let restarting { return await restarting.value }
        guard let connection else { return }
        let task = Task { await Self.terminate(connection, reason: reason) }
        self.connection = nil
        connectionFailed = false
        restarting = task
        await task.value
        restarting = nil
    }

    func restartIfFailed(reason: String) async {
        if let restarting { return await restarting.value }
        guard connectionFailed else { return }
        await restart(reason: reason)
    }

    /// The service process currently connected, if any (0 until the first reply).
    var servicePid: pid_t? {
        connection.map { xpc_connection_get_pid($0) }
    }

    // MARK: - Plumbing

    private static func terminate(_ connection: xpc_connection_t, reason: String) async {
        let pid = xpc_connection_get_pid(connection)
        PerfLog.logger.notice("restarting recognizer pid=\(pid, privacy: .public) reason=\(reason, privacy: .public)")
        let quit = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(quit, RecognizerProtocol.Key.op, RecognizerProtocol.Op.quit)
        xpc_connection_send_message(connection, quit)
        xpc_connection_cancel(connection)
        guard pid > 0 else { return }
        if await waitForExit(of: pid, within: .seconds(1)) { return }
        PerfLog.logger.notice("recognizer pid=\(pid, privacy: .public) ignored quit, killing it")
        kill(pid, SIGKILL)
        if await !waitForExit(of: pid, within: .seconds(2)) {
            PerfLog.logger.error("recognizer pid=\(pid, privacy: .public) still alive after SIGKILL")
        }
    }

    private func perform(_ message: xpc_object_t, timeout: Duration) async throws -> RecognizedLayout {
        if let restarting { await restarting.value }
        let connection = currentConnection()
        do {
            let reply = try await send(message, on: connection, timeout: timeout)
            return try Self.layout(from: reply)
        } catch {
            // Only blame the connection still in use: a reply that failed because another
            // caller already restarted the service says nothing about the new process.
            if connection === self.connection { connectionFailed = true }
            throw error
        }
    }

    private func currentConnection() -> xpc_connection_t {
        if let connection { return connection }
        let connection = xpc_connection_create(serviceName, queue)
        let name = serviceName
        xpc_connection_set_event_handler(connection) { event in
            // Only errors arrive here: replies go to their own handlers.
            guard xpc_get_type(event) == XPC_TYPE_ERROR else { return }
            let description = Self.describe(event)
            Logger(subsystem: PerfLog.subsystem, category: "perf")
                .notice("recognizer connection event: \(description, privacy: .public) service=\(name, privacy: .public)")
        }
        xpc_connection_activate(connection)
        self.connection = connection
        connectionFailed = false
        return connection
    }

    private func send(_ message: xpc_object_t, on connection: xpc_connection_t, timeout: Duration) async throws -> xpc_object_t {
        let gate = ReplyGate()
        let reply: xpc_object_t = try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            xpc_connection_send_message_with_reply(connection, message, queue) { reply in
                if xpc_get_type(reply) == XPC_TYPE_ERROR {
                    gate.resume(throwing: RecognitionTransportError.connection(Self.describe(reply)))
                } else {
                    gate.resume(returning: reply)
                }
            }
            queue.asyncAfter(deadline: .now() + timeout.timeInterval) {
                gate.resume(throwing: RecognitionTransportError.timedOut)
            }
        }
        return reply
    }

    private nonisolated static func layout(from reply: xpc_object_t) throws -> RecognizedLayout {
        if let error = xpc_dictionary_get_string(reply, RecognizerProtocol.Key.error) {
            throw RecognitionTransportError.vision(String(cString: error))
        }
        var length = 0
        guard let bytes = xpc_dictionary_get_data(reply, RecognizerProtocol.Key.layout, &length) else {
            throw RecognitionTransportError.malformed("reply without layout")
        }
        do {
            return try PropertyListDecoder().decode(RecognizedLayout.self, from: Data(bytes: bytes, count: length))
        } catch {
            throw RecognitionTransportError.malformed(String(describing: error))
        }
    }

    private nonisolated static func describe(_ error: xpc_object_t) -> String {
        if error === XPC_ERROR_CONNECTION_INTERRUPTED { return "interrupted" }
        if error === XPC_ERROR_CONNECTION_INVALID { return "invalid" }
        if let description = xpc_dictionary_get_string(error, XPC_ERROR_KEY_DESCRIPTION) {
            return String(cString: description)
        }
        return "unknown XPC error"
    }

    /// Polls for the process to be gone. `kill(pid, 0)` fails with `ESRCH` once it is reaped.
    private static func waitForExit(of pid: pid_t, within limit: Duration) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if kill(pid, 0) != 0, errno == ESRCH { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return kill(pid, 0) != 0 && errno == ESRCH
    }
}

/// Resumes a continuation once, whichever of the reply and the timeout comes first.
private final class ReplyGate: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var continuation: CheckedContinuation<xpc_object_t, Error>?

    func install(_ continuation: CheckedContinuation<xpc_object_t, Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func resume(returning value: xpc_object_t) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<xpc_object_t, Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let c = components
        return TimeInterval(c.seconds) + TimeInterval(c.attoseconds) / 1e18
    }
}
