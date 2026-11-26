import CoreGraphics
import Foundation

/// The wire format between the app and the `OCRSelectionRecognizer` XPC service.
///
/// Messages are plain XPC dictionaries: an `op` string, the image as raw pixels for
/// `recognize`, and a reply carrying either the Codable `RecognizedLayout` (binary
/// property list) or an error description. Compiled into both targets (`Shared/`).
enum RecognizerProtocol {
    enum Key {
        static let op = "op"
        static let width = "width"
        static let height = "height"
        static let bytesPerRow = "bytesPerRow"
        static let pixels = "pixels"
        /// Reply: the encoded `RecognizedLayout`.
        static let layout = "layout"
        /// Reply: Vision's error, described. Present instead of `layout` on failure.
        static let error = "error"
        /// Reply: how long the service spent in Vision, in milliseconds.
        static let elapsedMs = "elapsedMs"
    }

    enum Op {
        /// Recognise the attached image.
        static let recognize = "recognize"
        /// Recognise a small built-in image at low priority, so Vision loads, or compiles
        /// after a purge, its models before the user needs them.
        static let prewarm = "prewarm"
        /// Exit now. Sent before reconnecting, so the next connection gets a new process
        /// rather than the one whose Vision state is broken.
        static let quit = "quit"
    }

    /// The service's bundle identifier, derived from the app's: the Debug app
    /// (`….debug`) embeds `….debug.recognizer`, so the two builds never share a service,
    /// a TCC identity or a Vision cache (see the Debug isolation notes in CLAUDE.md).
    static func serviceName(forAppBundleID appBundleID: String) -> String {
        appBundleID + ".recognizer"
    }
}

/// A `CGImage` flattened to 8-bit BGRA pixels in sRGB, the form it crosses XPC in.
/// Raw pixels rather than PNG: copying them costs a few milliseconds, encoding a
/// full-screen capture as PNG costs hundreds.
struct ImagePayload: Sendable, Equatable {
    var width: Int
    var height: Int
    var bytesPerRow: Int
    var pixels: Data

    private static let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    init(width: Int, height: Int, bytesPerRow: Int, pixels: Data) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.pixels = pixels
    }

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: Self.bitmapInfo
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
    }

    func makeImage() -> CGImage? {
        guard width > 0, height > 0, bytesPerRow >= width * 4, pixels.count >= bytesPerRow * height,
              let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: Self.bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
