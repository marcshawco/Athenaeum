import Foundation
import CoreServices
import AppKit

// MARK: - Auto-Scan Coordinator
//
// Watches every enabled folder in `AutoScanRegistry` using a single
// FSEventStream (one stream, many paths). When Finder writes settle the
// coordinator scans each folder for files we haven't yet imported and hands
// the new URLs to the `DocumentProcessor`, which runs the standard extract +
// tag + index pipeline. Already-imported files are skipped by tracking the
// set of fingerprints (path + modification date) we've seen.

@MainActor
final class AutoScanCoordinator {
    private let registry: AutoScanRegistry
    private weak var processor: DocumentProcessor?

    /// FSEvents handle + security-scoped resources live on a nonisolated
    /// helper so we can release them from `deinit` without touching
    /// MainActor-isolated stored properties (which is a hard error under
    /// Swift 6 strict concurrency).
    private let streamHolder = StreamHolder()

    private var debounceWorkItem: DispatchWorkItem?

    private let eventQueue = DispatchQueue(label: "app.athenaeum.auto-scan")
    private let latency: CFTimeInterval = 2.0
    private let debounceDelay: TimeInterval = 2.5

    /// Cap on the in-session fingerprint set so a long-running install
    /// watching busy folders doesn't grow this dictionary unboundedly.
    /// LRU isn't worth the complexity here — when we hit the cap we
    /// simply drop the oldest insertions (Set has no insertion order,
    /// so we keep an array sidecar for FIFO eviction).
    private static let maxFingerprints = 50_000
    private var seenFingerprints: Set<String> = []
    private var fingerprintInsertionOrder: [String] = []

    private(set) var isRunning = false
    private(set) var lastError: String?

    /// Nonisolated holder for the C-pointer FSEvents stream and the
    /// security-scoped URLs we need to release together. Owns its own
    /// `NSLock` so `release()` can run from a nonisolated `deinit`.
    fileprivate final class StreamHolder: @unchecked Sendable {
        private let lock = NSLock()
        private var stream: FSEventStreamRef?
        private var securityScopedURLs: [URL] = []

        func set(stream: FSEventStreamRef?, securityScopedURLs: [URL]) {
            lock.withLock {
                self.stream = stream
                self.securityScopedURLs = securityScopedURLs
            }
        }

        var hasStream: Bool {
            lock.withLock { stream != nil }
        }

        func release() {
            lock.withLock {
                if let s = stream {
                    FSEventStreamStop(s)
                    FSEventStreamInvalidate(s)
                    FSEventStreamRelease(s)
                }
                stream = nil
                for u in securityScopedURLs { u.stopAccessingSecurityScopedResource() }
                securityScopedURLs.removeAll()
            }
        }
    }

    init(registry: AutoScanRegistry) {
        self.registry = registry
    }

    func attach(processor: DocumentProcessor) {
        self.processor = processor
    }

    // MARK: - Lifecycle

    func restart() {
        stop()
        let enabled = registry.folders.filter { $0.isEnabled }
        let urls = enabled.compactMap { registry.resolveURL(for: $0) }
        guard !urls.isEmpty else { return }
        start(urls: urls)
        // Do an initial scan so existing folder contents are picked up.
        triggerScan()
    }

    private func start(urls: [URL]) {
        // Track each successful start-access so stop() pairs each one
        // with a matching stopAccessingSecurityScopedResource() — the
        // OS-level retain count is per-call, not per-URL.
        var heldURLs: [URL] = []
        for url in urls where url.startAccessingSecurityScopedResource() {
            heldURLs.append(url)
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            autoScanEventCallback,
            &context,
            urls.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            lastError = "Could not create auto-scan watcher."
            for u in heldURLs { u.stopAccessingSecurityScopedResource() }
            return
        }
        FSEventStreamSetDispatchQueue(stream, eventQueue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            for u in heldURLs { u.stopAccessingSecurityScopedResource() }
            lastError = "Could not start auto-scan watcher."
            return
        }
        streamHolder.set(stream: stream, securityScopedURLs: heldURLs)
        isRunning = true
        lastError = nil
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        streamHolder.release()
        isRunning = false
    }

    /// Called from the FSEvents callback (background queue). Schedules a
    /// debounced jump back to the main actor to actually run the scan.
    nonisolated fileprivate func scheduleScan() {
        Task { @MainActor [weak self] in
            self?.scheduleScanOnMain()
        }
    }

    private func scheduleScanOnMain() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in self?.triggerScan() }
        }
        debounceWorkItem = work
        eventQueue.asyncAfter(deadline: .now() + debounceDelay, execute: work)
    }

    private func triggerScan() {
        guard let processor else { return }
        let enabled = registry.folders.filter { $0.isEnabled }
        let allowed = AutoScanCoordinator.supportedExtensions

        var freshURLs: [URL] = []
        for folder in enabled {
            guard let folderURL = registry.resolveURL(for: folder) else { continue }
            let accessing = folderURL.startAccessingSecurityScopedResource()
            defer { if accessing { folderURL.stopAccessingSecurityScopedResource() } }

            guard let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .isSymbolicLinkKey])
                // Skip symlinks defensively — a hostile auto-scan folder
                // could otherwise expose anything reachable via a link
                // (e.g. ~/Library/Mail) to the import pipeline.
                guard values?.isSymbolicLink != true else { continue }
                guard values?.isRegularFile == true else { continue }
                guard allowed.contains(fileURL.pathExtension.lowercased()) else { continue }
                let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                let fingerprint = "\(fileURL.standardizedFileURL.path)|\(Int(mtime))"
                if seenFingerprints.contains(fingerprint) { continue }
                rememberFingerprint(fingerprint)
                freshURLs.append(fileURL)
            }
        }

        guard !freshURLs.isEmpty else { return }
        Task { @MainActor in
            _ = await processor.importFiles(freshURLs)
        }
    }

    private func rememberFingerprint(_ fingerprint: String) {
        seenFingerprints.insert(fingerprint)
        fingerprintInsertionOrder.append(fingerprint)
        if fingerprintInsertionOrder.count > Self.maxFingerprints {
            // Drop the oldest 10% in one pass so this isn't every call.
            let drop = Self.maxFingerprints / 10
            let evicted = fingerprintInsertionOrder.prefix(drop)
            for fp in evicted { seenFingerprints.remove(fp) }
            fingerprintInsertionOrder.removeFirst(drop)
        }
    }

    deinit {
        // `streamHolder` is a separate class (not MainActor-isolated)
        // so calling release() here is safe under Swift 6's stricter
        // nonisolated-deinit rules. No MainActor stored properties are
        // touched from this deinit.
        streamHolder.release()
    }

    // MARK: - Supported file types

    /// Single source of truth for "what extensions Athenaeum can ingest".
    /// Kept in sync with the file pickers and the folder-import flow.
    static let supportedExtensions: Set<String> = [
        // Office / text
        "pdf", "rtf", "rtfd", "txt", "md", "markdown", "html", "htm",
        "doc", "docx", "odt", "pages",
        // Spreadsheets
        "csv", "tsv", "xls", "xlsx", "numbers",
        // Presentations
        "ppt", "pptx", "key",
        // Email / EPUB
        "eml", "msg", "epub",
        // Code / config (treated as plain text for indexing)
        "swift", "py", "js", "ts", "tsx", "jsx", "go", "rs", "rb", "java",
        "kt", "c", "cc", "cpp", "h", "hpp", "m", "mm", "sh", "zsh", "bash",
        "json", "yaml", "yml", "toml", "ini", "conf", "log", "xml", "plist",
        // Images (OCR via Apple Vision)
        "png", "jpg", "jpeg", "tif", "tiff", "heic", "heif", "webp", "gif", "bmp",
    ]
}

private let autoScanEventCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
    guard let info else { return }
    let coordinator = Unmanaged<AutoScanCoordinator>.fromOpaque(info).takeUnretainedValue()
    coordinator.scheduleScan()
}
