import CoreGraphics
import Foundation
import Testing
@testable import OCRSelection

@MainActor
struct OCRServiceRetryTests {
    private static let layout = RecognizedLayout(fragments: [
        .init(text: "Hello", frame: CGRect(x: 10, y: 10, width: 100, height: 20))
    ])

    @Test func successNeedsNoRestart() async throws {
        let transport = StubTransport([.success(Self.layout)])
        let text = try await OCRService(transport: transport).recognizeText(in: dummyImage())
        #expect(text == "Hello")
        #expect(transport.recognizeCalls == 1)
        #expect(transport.restarts.isEmpty)
    }

    @Test func visionFailureRestartsAndRetriesTheSameImage() async throws {
        let transport = StubTransport([.failure(.vision("e5rtError 13")), .success(Self.layout)])
        let text = try await OCRService(transport: transport).recognizeText(in: dummyImage(width: 7, height: 5))
        #expect(text == "Hello")
        #expect(transport.recognizeCalls == 2)
        #expect(transport.restarts.count == 1)
        #expect(transport.images.map(\.width) == [7, 7])
        #expect(transport.images.first == transport.images.last)
        // The restart happened between the two attempts.
        #expect(transport.log == ["recognize", "restart", "recognize"])
    }

    @Test func interruptedConnectionIsRetried() async throws {
        let transport = StubTransport([.failure(.connection("interrupted")), .success(Self.layout)])
        let text = try await OCRService(transport: transport).recognizeText(in: dummyImage())
        #expect(text == "Hello")
        #expect(transport.log == ["recognize", "restart", "recognize"])
    }

    @Test func secondFailureSurfacesAsVisionFailed() async {
        let transport = StubTransport([.failure(.vision("first")), .failure(.vision("second"))])
        await #expect {
            _ = try await OCRService(transport: transport).recognizeText(in: dummyImage())
        } throws: { error in
            guard case OCRError.visionFailed(let underlying) = error,
                  case RecognitionTransportError.vision("second") = underlying else { return false }
            return true
        }
        #expect(transport.recognizeCalls == 2)
        // A fresh process is left for the next capture.
        #expect(transport.log == ["recognize", "restart", "recognize", "restart"])
    }

    @Test func timeoutRestartsWithoutRetrying() async {
        let transport = StubTransport([.failure(.timedOut), .success(Self.layout)])
        await #expect {
            _ = try await OCRService(transport: transport).recognizeText(in: dummyImage())
        } throws: { error in
            guard case OCRError.visionFailed(RecognitionTransportError.timedOut) = error else { return false }
            return true
        }
        #expect(transport.log == ["recognize", "restart"])
    }

    @Test func timeoutIsPassedToEveryAttempt() async throws {
        let transport = StubTransport([.failure(.vision("x")), .success(Self.layout)])
        _ = try await OCRService(transport: transport, timeout: .seconds(42)).recognizeText(in: dummyImage())
        #expect(transport.timeouts == [.seconds(42), .seconds(42)])
    }

    @Test func emptyLayoutIsNoTextFound() async {
        let transport = StubTransport([.success(RecognizedLayout(fragments: []))])
        await #expect {
            _ = try await OCRService(transport: transport).recognizeText(in: dummyImage())
        } throws: { error in
            guard case OCRError.noTextFound = error else { return false }
            return true
        }
        #expect(transport.restarts.isEmpty)
    }

    @Test func imagePayloadRoundTrips() throws {
        let image = dummyImage(width: 9, height: 4)
        let payload = try #require(ImagePayload(image))
        #expect(payload.width == 9)
        #expect(payload.height == 4)
        #expect(payload.pixels.count == 9 * 4 * 4)
        let decoded = try #require(payload.makeImage())
        #expect(decoded.width == 9)
        #expect(decoded.height == 4)
        #expect(ImagePayload(decoded) == payload)
    }
}

@MainActor
final class StubTransport: RecognitionTransport {
    private var results: [Result<RecognizedLayout, RecognitionTransportError>]
    private(set) var images: [ImagePayload] = []
    private(set) var timeouts: [Duration] = []
    private(set) var restarts: [String] = []
    private(set) var prewarms = 0
    private(set) var log: [String] = []
    var prewarmHook: (() -> Void)?
    var recognizeCalls: Int { images.count }

    init(_ results: [Result<RecognizedLayout, RecognitionTransportError>]) {
        self.results = results
    }

    func recognize(_ image: ImagePayload, timeout: Duration) async throws -> RecognizedLayout {
        images.append(image)
        timeouts.append(timeout)
        log.append("recognize")
        guard !results.isEmpty else { throw RecognitionTransportError.connection("no stubbed result") }
        return try results.removeFirst().get()
    }

    func prewarm(timeout: Duration) async throws {
        prewarms += 1
        log.append("prewarm")
        prewarmHook?()
    }

    func restart(reason: String) async {
        restarts.append(reason)
        log.append("restart")
    }

    func restartIfFailed(reason: String) async {
        await restart(reason: reason)
    }
}

private func dummyImage(width: Int = 2, height: Int = 2) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}
