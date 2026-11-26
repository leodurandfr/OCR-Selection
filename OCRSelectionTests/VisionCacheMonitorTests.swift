import Foundation
import Testing
@testable import OCRSelection

/// Drives the monitor against a temporary folder shaped like Vision's cache, with a stub
/// transport: no Vision, no real `~/Library/Caches`.
@MainActor
struct VisionCacheMonitorTests {
    @Test func launchPrewarmsAndRecordsTheModels() async throws {
        let root = try makeCache(bundles: 3)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = StubTransport([])
        let monitor = VisionCacheMonitor(cacheRoot: root, transport: transport, coalescingDelay: .milliseconds(50))
        await monitor.rebuild(reason: "test")
        #expect(transport.prewarms == 1)
        #expect(monitor.knownBundleCount == 3)
    }

    @Test func inProgressCompilesDoNotCount() throws {
        let root = try makeCache(bundles: 2, temporaryBundles: 2)
        defer { try? FileManager.default.removeItem(at: root) }
        let monitor = VisionCacheMonitor(cacheRoot: root, transport: StubTransport([]))
        #expect(monitor.countModelBundles() == 2)
    }

    @Test func purgeRestartsAndPrewarmsAgain() async throws {
        let root = try makeCache(bundles: 3)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = StubTransport([])
        let monitor = VisionCacheMonitor(cacheRoot: root, transport: transport)
        await monitor.rebuild(reason: "launch")

        // What `deleted` did: the OS-build folder emptied.
        let build = monitor.bundleCacheDirectory.appending(path: "26B131")
        for item in try FileManager.default.contentsOfDirectory(at: build, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: item)
        }
        // The rebuild compiles the models again.
        transport.prewarmHook = { try? addBundles(3, to: root) }
        await monitor.check()

        #expect(transport.log == ["prewarm", "restart", "prewarm"])
        #expect(transport.restarts == ["vision cache purged"])
        #expect(monitor.knownBundleCount == 3)
    }

    @Test func purgedSkeletonsDoNotCount() async throws {
        let root = try makeCache(bundles: 4)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = StubTransport([])
        let monitor = VisionCacheMonitor(cacheRoot: root, transport: transport)
        await monitor.rebuild(reason: "launch")
        #expect(monitor.knownBundleCount == 4)

        // What the purge really does: files gone, folders left.
        try purgeFiles(in: root)
        #expect(monitor.countModelBundles() == 0)
        transport.prewarmHook = { try? addBundles(4, to: root) }
        await monitor.check()
        #expect(transport.log == ["prewarm", "restart", "prewarm"])
    }

    @Test func purgeDuringACaptureDefersTheRestart() async throws {
        let root = try makeCache(bundles: 3)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = StubTransport([])
        let monitor = VisionCacheMonitor(cacheRoot: root, transport: transport)
        await monitor.rebuild(reason: "launch")
        var recognizing = true
        monitor.isRecognizing = { recognizing }

        try purgeFiles(in: root)
        await monitor.check()
        #expect(transport.restarts.isEmpty)

        // The capture's OCR recompiled the models; once it is done nothing is missing.
        try addBundles(3, to: root)
        recognizing = false
        await monitor.check()
        #expect(transport.restarts.isEmpty)
        #expect(transport.log == ["prewarm"])
    }

    @Test func extraModelIsNotAPurge() async throws {
        let root = try makeCache(bundles: 3)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = StubTransport([])
        let monitor = VisionCacheMonitor(cacheRoot: root, transport: transport)
        await monitor.rebuild(reason: "launch")
        try addBundles(1, to: root)
        await monitor.check()
        #expect(transport.log == ["prewarm"])
        #expect(monitor.knownBundleCount == 4)
    }

    @Test func missingCacheFolderIsHandled() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "vision-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = StubTransport([])
        transport.prewarmHook = { try? addBundles(2, to: root) }
        let monitor = VisionCacheMonitor(cacheRoot: root, transport: transport)
        #expect(monitor.countModelBundles() == 0)
        await monitor.rebuild(reason: "first launch")
        #expect(monitor.knownBundleCount == 2)
    }

    @Test func fileSystemEventsTriggerACoalescedCheck() async throws {
        let root = try makeCache(bundles: 2)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = StubTransport([])
        let monitor = VisionCacheMonitor(cacheRoot: root, transport: transport, coalescingDelay: .milliseconds(100))
        monitor.start()
        defer { monitor.stop() }
        while transport.prewarms < 1 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))

        // Several changes at once, as a purge makes: one restart, one rebuild.
        transport.prewarmHook = { try? addBundles(2, to: root) }
        try FileManager.default.removeItem(at: monitor.bundleCacheDirectory)
        let deadline = ContinuousClock.now + .seconds(5)
        while transport.prewarms < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(transport.restarts == ["vision cache purged"])
        #expect(transport.prewarms == 2)
    }
}

private func makeCache(bundles: Int, temporaryBundles: Int = 0) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "vision-cache-\(UUID().uuidString)")
    try addBundles(bundles, to: root)
    let build = root.appending(path: "com.apple.e5rt.e5bundlecache/26B131")
    for index in 0..<temporaryBundles {
        let hash = build.appending(path: "TMP\(index)")
        try writeModelFile(in: hash.appending(path: "ABC.tmp.123_\(index).bundle"))
    }
    return root
}

private func addBundles(_ count: Int, to root: URL) throws {
    let build = root.appending(path: "com.apple.e5rt.e5bundlecache/26B131")
    for _ in 0..<count {
        let hash = UUID().uuidString
        try writeModelFile(in: build.appending(path: hash).appending(path: "\(hash).bundle"))
    }
}

/// What e5rt writes: `<hash>.bundle/H16S.bundle/H16S.e5` among others.
private func writeModelFile(in bundle: URL) throws {
    let directory = bundle.appending(path: "H16S.bundle")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("model".utf8).write(to: directory.appending(path: "H16S.e5"))
}

/// What the purge leaves: the folders of every bundle, none of the files.
private func purgeFiles(in root: URL) throws {
    let fm = FileManager.default
    let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
    var files: [URL] = []
    while let item = enumerator?.nextObject() as? URL {
        if (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { files.append(item) }
    }
    for file in files { try fm.removeItem(at: file) }
}
