import CoreGraphics
import Foundation
import os
import XPC

/// Entry point of the `OCRSelectionRecognizer` XPC service, embedded in the app's
/// `Contents/XPCServices`. It runs Vision and nothing else: the app sends pixels, the
/// service answers with a Vision-free `RecognizedLayout`, and the app's `TextAssembler`
/// turns that into text.
///
/// Why a separate process: when the disk is nearly full macOS purges Vision's compiled
/// Neural Engine model from `~/Library/Caches/<bundle ID>/com.apple.e5rt.e5bundlecache`.
/// A process that had the model loaded then fails every recognition with `e5rtError … 13`
/// until it exits — retrying in process, even pinned to the CPU, fails the same way. The
/// app can kill this process and get a fresh one, which recompiles the model and works.
///
/// The service has its own bundle ID, so its Vision cache is
/// `~/Library/Caches/<service bundle ID>`, which the app watches (`VisionCacheMonitor`).

/// Same `BEGINSWITH "com.leodurand.ocr-selection"` log predicate as the app.
let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.leodurand.ocr-selection.recognizer", category: "recognizer")

enum RecognizerService {
    static func handle(_ message: xpc_object_t, from peer: xpc_connection_t) {
        guard let op = xpc_dictionary_get_string(message, RecognizerProtocol.Key.op).map({ String(cString: $0) }) else { return }
        switch op {
        case RecognizerProtocol.Op.quit:
            log.notice("recognizer quitting on request")
            exit(0)
        case RecognizerProtocol.Op.prewarm:
            let images = TextRecognition.prewarmImages()
            guard let last = images.last else {
                reply(to: message, on: peer, error: "prewarm image could not be drawn")
                return
            }
            // Low priority: a rebuild after a purge must not compete with what the user
            // is doing. A capture arriving meanwhile is handled by its own task. One image
            // after the other, replying once with the last.
            Task(priority: .utility) {
                for image in images.dropLast() {
                    _ = try? await TextRecognition.recognize(image)
                }
                await run(last, replyingTo: message, on: peer, label: "prewarm")
            }
        case RecognizerProtocol.Op.recognize:
            guard let image = payload(from: message)?.makeImage() else {
                reply(to: message, on: peer, error: "malformed image payload")
                return
            }
            Task(priority: .userInitiated) { await run(image, replyingTo: message, on: peer, label: "recognize") }
        default:
            reply(to: message, on: peer, error: "unknown op \(op)")
        }
    }

    private static func run(_ image: CGImage, replyingTo message: xpc_object_t, on peer: xpc_connection_t, label: String) async {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let layout = try await TextRecognition.recognize(image)
            let elapsed = milliseconds(clock.now - start)
            let encoded = try PropertyListEncoder.binary.encode(layout)
            log.notice("\(label, privacy: .public) ok fragments=\(layout.fragments.count, privacy: .public) vision=\(elapsed, privacy: .public)ms")
            guard let reply = xpc_dictionary_create_reply(message) else { return }
            encoded.withUnsafeBytes { buffer in
                xpc_dictionary_set_data(reply, RecognizerProtocol.Key.layout, buffer.baseAddress!, buffer.count)
            }
            xpc_dictionary_set_int64(reply, RecognizerProtocol.Key.elapsedMs, Int64(elapsed))
            xpc_connection_send_message(peer, reply)
        } catch {
            log.error("\(label, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            reply(to: message, on: peer, error: String(describing: error))
        }
    }

    private static func reply(to message: xpc_object_t, on peer: xpc_connection_t, error: String) {
        guard let reply = xpc_dictionary_create_reply(message) else { return }
        xpc_dictionary_set_string(reply, RecognizerProtocol.Key.error, error)
        xpc_connection_send_message(peer, reply)
    }

    private static func payload(from message: xpc_object_t) -> ImagePayload? {
        var length = 0
        guard let bytes = xpc_dictionary_get_data(message, RecognizerProtocol.Key.pixels, &length) else { return nil }
        return ImagePayload(
            width: Int(xpc_dictionary_get_int64(message, RecognizerProtocol.Key.width)),
            height: Int(xpc_dictionary_get_int64(message, RecognizerProtocol.Key.height)),
            bytesPerRow: Int(xpc_dictionary_get_int64(message, RecognizerProtocol.Key.bytesPerRow)),
            pixels: Data(bytes: bytes, count: length)
        )
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let c = duration.components
        return Int(c.seconds) * 1_000 + Int(c.attoseconds / 1_000_000_000_000_000)
    }
}

extension PropertyListEncoder {
    static var binary: PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }
}

log.notice("recognizer started pid=\(getpid(), privacy: .public)")
xpc_main { peer in
    xpc_connection_set_event_handler(peer) { event in
        guard xpc_get_type(event) == XPC_TYPE_DICTIONARY else { return }
        RecognizerService.handle(event, from: peer)
    }
    xpc_connection_activate(peer)
}
