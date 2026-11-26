import Foundation

/// Keeps Vision's compiled model ready, so a capture never pays the 30–60 s recompile.
///
/// The recognizer service's compiled Neural Engine models live in
/// `~/Library/Caches/<service bundle ID>/com.apple.e5rt.e5bundlecache/<OS build>/<hash>/<hash>.bundle`.
/// When the disk is nearly full macOS's `deleted` daemon purges that folder. This monitor:
///
/// - **prewarms at launch**: one tiny OCR in the service at low priority, which loads the
///   models, or compiles them after an install, an OS update or a purge;
/// - **watches the cache** with `DispatchSource` file-system sources on every folder down
///   to the model bundles (the purge was seen emptying the folders rather than removing
///   the top one), re-armed after every change, and counts the finished `.bundle`s. When
///   the count drops, the models were purged: the service, which may hold them loaded and
///   would then fail with `e5rtError … 13`, is restarted and prewarmed again.
///
/// Events are coalesced (a purge or a compile touches many folders at once) and ignored
/// while a rebuild runs, since the rebuild itself writes the cache. None of this drives
/// the menu-bar pulse, which stays for user-initiated OCR only.
@MainActor
final class VisionCacheMonitor {
    let cacheRoot: URL
    private let transport: any RecognitionTransport
    private let coalescingDelay: Duration
    private let prewarmTimeout: Duration
    private var sources: [String: any DispatchSourceFileSystemObject] = [:]
    private var pendingCheck: Task<Void, Never>?
    private var isRebuilding = false
    /// Finished model bundles last seen after a successful prewarm or check.
    private(set) var knownBundleCount = 0

    /// `cacheRoot` is `~/Library/Caches/<service bundle ID>`.
    init(
        cacheRoot: URL,
        transport: any RecognitionTransport,
        coalescingDelay: Duration = .seconds(3),
        prewarmTimeout: Duration = .seconds(180)
    ) {
        self.cacheRoot = cacheRoot
        self.transport = transport
        self.coalescingDelay = coalescingDelay
        self.prewarmTimeout = prewarmTimeout
    }

    static func defaultCacheRoot(serviceName: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches", directoryHint: .isDirectory)
            .appending(path: serviceName, directoryHint: .isDirectory)
    }

    var bundleCacheDirectory: URL {
        cacheRoot.appending(path: "com.apple.e5rt.e5bundlecache", directoryHint: .isDirectory)
    }

    func start() {
        // The service would create it on first use anyway; creating it now gives the
        // watcher something to open before Vision has ever run.
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        rearm()
        Task { await rebuild(reason: "launch") }
    }

    func stop() {
        pendingCheck?.cancel()
        sources.values.forEach { $0.cancel() }
        sources.removeAll()
    }

    /// Prewarms the service and records how many model bundles that left in the cache.
    func rebuild(reason: String) async {
        guard !isRebuilding else { return }
        isRebuilding = true
        defer { isRebuilding = false }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try await transport.prewarm(timeout: prewarmTimeout)
            knownBundleCount = countModelBundles()
            PerfLog.logger.notice(
                """
                vision model ready reason=\(reason, privacy: .public) \
                duration=\(String(format: "%.0f", PerfLog.milliseconds(clock.now - start)), privacy: .public)ms \
                bundles=\(self.knownBundleCount, privacy: .public)
                """
            )
        } catch {
            // Not retried in a loop: the next capture retries on its own, and the next
            // cache change triggers another check.
            knownBundleCount = countModelBundles()
            PerfLog.logger.error("vision prewarm failed reason=\(reason, privacy: .public): \(String(describing: error), privacy: .public)")
            await transport.restartIfFailed(reason: "prewarm failed")
        }
        rearm()
    }

    /// Compares the cache with what the last rebuild left; rebuilds if models went missing.
    func check() async {
        rearm()
        guard !isRebuilding else { return }
        let count = countModelBundles()
        if count < knownBundleCount {
            PerfLog.logger.notice("vision cache purged: bundles=\(count, privacy: .public) was=\(self.knownBundleCount, privacy: .public)")
            await transport.restart(reason: "vision cache purged")
            await rebuild(reason: "purge")
        } else {
            // A capture in another language can compile one more model: it is the new norm.
            knownBundleCount = count
        }
    }

    /// Finished model bundles, at `<OS build>/<hash>/<hash>.bundle`. In-progress compiles
    /// (`<hash>.tmp.<pid>_<n>.bundle`) don't count.
    func countModelBundles() -> Int {
        let fm = FileManager.default
        var count = 0
        for build in Self.subdirectories(of: bundleCacheDirectory) {
            for hash in Self.subdirectories(of: build) {
                let names = (try? fm.contentsOfDirectory(atPath: hash.path)) ?? []
                count += names.filter { $0.hasSuffix(".bundle") && !$0.contains(".tmp.") }.count
            }
        }
        return count
    }

    // MARK: - Watching

    private func scheduleCheck() {
        pendingCheck?.cancel()
        pendingCheck = Task { [coalescingDelay] in
            do { try await Task.sleep(for: coalescingDelay) } catch { return }
            await check()
        }
    }

    /// Watches the cache root, the bundle cache, and every OS-build and hash folder in it.
    /// Rebuilt after each change, since folders come and go.
    private func rearm() {
        var wanted = [cacheRoot, bundleCacheDirectory]
        for build in Self.subdirectories(of: bundleCacheDirectory) {
            wanted.append(build)
            wanted.append(contentsOf: Self.subdirectories(of: build))
        }
        let wantedPaths = Set(wanted.map(\.path))
        for (path, source) in sources where !wantedPaths.contains(path) {
            source.cancel()
            sources[path] = nil
        }
        for path in wantedPaths where sources[path] == nil {
            // O_EVTONLY: watching must not keep the volume busy or block the purge.
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue } // Not created yet: the parent's watch sees it appear.
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .link, .revoke],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleCheck() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources[path] = source
        }
    }

    private static func subdirectories(of url: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url.resolvingSymlinksInPath(),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}
