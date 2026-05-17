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

    private var stream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private var securityScopedURLs: [URL] = []

    private let eventQueue = DispatchQueue(label: "app.athenaeum.auto-scan")
    private let latency: CFTimeInterval = 2.0
    private let debounceDelay: TimeInterval = 2.5

    /// Files already handed to the processor in this session, identified by
    /// `path|mtime` so a touched-but-unchanged file doesn't get re-imported.
    private var seenFingerprints: Set<String> = []

    private(set) var isRunning = false
    private(set) var lastError: String?

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
        securityScopedURLs = urls
        for url in urls { _ = url.startAccessingSecurityScopedResource() }

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
            releaseSecurityScopes()
            return
        }
        FSEventStreamSetDispatchQueue(stream, eventQueue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            releaseSecurityScopes()
            lastError = "Could not start auto-scan watcher."
            return
        }
        self.stream = stream
        isRunning = true
        lastError = nil
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        isRunning = false
        releaseSecurityScopes()
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
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
                guard values?.isRegularFile == true else { continue }
                guard allowed.contains(fileURL.pathExtension.lowercased()) else { continue }
                let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                let fingerprint = "\(fileURL.standardizedFileURL.path)|\(Int(mtime))"
                if seenFingerprints.contains(fingerprint) { continue }
                seenFingerprints.insert(fingerprint)
                freshURLs.append(fileURL)
            }
        }

        guard !freshURLs.isEmpty else { return }
        Task { @MainActor in
            _ = await processor.importFiles(freshURLs)
        }
    }

    private func releaseSecurityScopes() {
        for url in securityScopedURLs { url.stopAccessingSecurityScopedResource() }
        securityScopedURLs.removeAll()
    }

    deinit {
        // Stop stream synchronously without main-actor jump.
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        for url in securityScopedURLs { url.stopAccessingSecurityScopedResource() }
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
