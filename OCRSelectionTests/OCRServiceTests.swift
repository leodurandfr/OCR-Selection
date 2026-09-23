import AppKit
import CoreGraphics
import CoreText
import Testing
@testable import OCRSelection

@MainActor
struct OCRServiceTests {
    @Test func recognizesKnownText() async throws {
        let image = try renderFixture(text: "Hello World")
        let service = OCRService()
        let result = try await service.recognizeText(in: image)
        #expect(result.contains("Hello"))
        #expect(result.contains("World"))
    }

    /// The fallback path used when Vision fails on the Neural Engine.
    @Test func recognizesKnownTextOnCPU() async throws {
        let image = try renderFixture(text: "Hello World")
        let result = try await OCRService.visionPass(image, cpuOnly: true)
        #expect(result.contains("Hello"))
        #expect(result.contains("World"))
    }

    @Test func neuralEngineFailureRetriesOnCPUAndStaysThere() async throws {
        let pass = ScriptedPass([.failure(visionError), .success("first"), .success("second")])
        let service = OCRService(pass: pass.run)
        let image = try renderFixture(text: "x")

        #expect(try await service.recognizeText(in: image) == "first")
        #expect(try await service.recognizeText(in: image) == "second")
        #expect(pass.cpuOnlyCalls == [false, true, true])
    }

    @Test func noTextOnCPURetryStillSwitchesToCPU() async throws {
        let pass = ScriptedPass([.failure(visionError), .failure(OCRError.noTextFound), .success("next")])
        let service = OCRService(pass: pass.run)
        let image = try renderFixture(text: "x")

        await #expect(throws: OCRError.self) { try await service.recognizeText(in: image) }
        #expect(try await service.recognizeText(in: image) == "next")
        #expect(pass.cpuOnlyCalls == [false, true, true])
    }

    @Test func failureOnBothDevicesDoesNotSwitch() async throws {
        let pass = ScriptedPass([.failure(visionError), .failure(visionError), .success("next")])
        let service = OCRService(pass: pass.run)
        let image = try renderFixture(text: "x")

        await #expect(throws: OCRError.self) { try await service.recognizeText(in: image) }
        #expect(try await service.recognizeText(in: image) == "next")
        #expect(pass.cpuOnlyCalls == [false, true, false])
    }

    @Test func noTextOnDefaultDeviceIsNotRetried() async throws {
        let pass = ScriptedPass([.failure(OCRError.noTextFound)])
        let service = OCRService(pass: pass.run)

        await #expect(throws: OCRError.self) { try await service.recognizeText(in: try renderFixture(text: "x")) }
        #expect(pass.cpuOnlyCalls == [false])
    }
}

private struct VisionBoom: Error {}
private let visionError = OCRError.visionFailed(VisionBoom())

/// Replays scripted results in order and records which device each pass asked for.
@MainActor private final class ScriptedPass {
    private var results: [Result<String, Error>]
    private(set) var cpuOnlyCalls: [Bool] = []

    init(_ results: [Result<String, Error>]) { self.results = results }

    func run(_ image: CGImage, cpuOnly: Bool) async throws -> String {
        cpuOnlyCalls.append(cpuOnly)
        guard !results.isEmpty else {
            Issue.record("unexpected extra Vision pass")
            throw OCRError.noTextFound
        }
        return try results.removeFirst().get()
    }
}

private func renderFixture(text: String) throws -> CGImage {
    let size = CGSize(width: 800, height: 200)
    guard let context = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw FixtureError.contextCreationFailed
    }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 80, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attributed)
    context.textPosition = CGPoint(x: 40, y: 60)
    CTLineDraw(line, context)
    guard let image = context.makeImage() else { throw FixtureError.renderFailed }
    return image
}

private enum FixtureError: Error {
    case contextCreationFailed
    case renderFailed
}
