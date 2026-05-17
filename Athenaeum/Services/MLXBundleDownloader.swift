import Foundation

// MARK: - MLX Bundle Downloader
//
// Downloads the multi-file Hugging Face snapshot for a single MLXBundleDescriptor
// into its on-disk directory. Files are fetched serially with a native
// URLSessionDownloadTask per file so the kernel handles chunked I/O and we get
// smooth progress updates even on a 4 GB safetensors blob.
//
// We deliberately keep this independent of `ModelDownloader` (which is keyed
// by LLMRole + assumes one file per model). MLX bundles aren't role-keyed and
// span multiple files, so a separate downloader keeps each side clean.

@Observable
final class MLXBundleDownloader {
    /// Active download state per bundle id. Absent = idle.
    private(set) var states: [String: BundleDownloadState] = [:]

    private var cancelledBundleIDs: Set<String> = []

    private var runningTasks: [String: Task<Void, Never>] = [:]

    private let manager: MLXModelManager

    /// One shared `URLSession` for the lifetime of this downloader. Allocating
    /// a new session per file (the old computed-property bug) loses connection
    /// reuse and made cancellation unreliable.
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 7200
        cfg.httpAdditionalHeaders = [
            "User-Agent": "ATHENS/1.0 (+local)"
        ]
        return URLSession(configuration: cfg)
    }()

    init(manager: MLXModelManager) {
        self.manager = manager
    }

    struct BundleDownloadState: Sendable {
        var status: Status
        var progress: Double          // 0...1 across the whole bundle
        var bytesWritten: Int64       // cumulative across all files
        var totalBytes: Int64
        var currentFile: String       // file currently being fetched
        var currentFileBytes: Int64   // bytes streamed so far for currentFile
        var currentFileTotal: Int64   // expected size of currentFile from headers
        var failureMessage: String?

        enum Status: String, Sendable {
            case downloading, completed, failed, cancelled
        }
    }

    // MARK: - Public API

    func startDownload(_ descriptor: MLXBundleDescriptor) {
        // Don't re-enter if already running.
        if let s = states[descriptor.id], s.status == .downloading { return }
        cancelledBundleIDs.remove(descriptor.id)
        states[descriptor.id] = BundleDownloadState(
            status: .downloading,
            progress: 0,
            bytesWritten: 0,
            totalBytes: descriptor.expectedSize,
            currentFile: descriptor.files.first ?? "",
            currentFileBytes: 0,
            currentFileTotal: 0,
            failureMessage: nil
        )

        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.runDownload(descriptor)
        }
        runningTasks[descriptor.id] = task
    }

    func cancelDownload(_ descriptor: MLXBundleDescriptor) {
        cancelledBundleIDs.insert(descriptor.id)
        states[descriptor.id]?.status = .cancelled
        runningTasks[descriptor.id]?.cancel()
        runningTasks.removeValue(forKey: descriptor.id)
    }

    func clearFinishedState(_ descriptor: MLXBundleDescriptor) {
        states.removeValue(forKey: descriptor.id)
    }

    // MARK: - Driver

    /// Files we tolerate being absent (HF returns 404). The bundle is
    /// considered complete as long as the required files all land.
    private static let optionalFiles: Set<String> = [
        "model.safetensors.index.json",   // only present on sharded repos
        "added_tokens.json",
        "merges.txt",
        "chat_template.jinja",
    ]

    private func runDownload(_ descriptor: MLXBundleDescriptor) async {
        let dir = manager.directory(for: descriptor)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var aggregateWritten: Int64 = 0
        let expectedTotal = descriptor.expectedSize

        for filename in descriptor.files {
            if cancelledBundleIDs.contains(descriptor.id) { return }

            await MainActor.run {
                states[descriptor.id]?.currentFile = filename
                states[descriptor.id]?.currentFileBytes = 0
                states[descriptor.id]?.currentFileTotal = 0
            }

            let url = huggingFaceURL(repo: descriptor.repoID, revision: descriptor.revision, filename: filename)
            let dest = dir.appendingPathComponent(filename)

            // Skip-if-complete lets a partial bundle resume on retry.
            if FileManager.default.fileExists(atPath: dest.path),
               let size = try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber,
               size.int64Value > 1024 {            // > tiny error-page sized
                aggregateWritten += size.int64Value
                updateBundleProgress(descriptor.id, written: aggregateWritten, total: expectedTotal)
                continue
            }

            do {
                let bytesDownloaded = try await downloadFileStreaming(
                    bundleID: descriptor.id,
                    url: url,
                    destination: dest,
                    aggregateAlreadyWritten: aggregateWritten,
                    expectedBundleTotal: expectedTotal
                )
                aggregateWritten += bytesDownloaded
                updateBundleProgress(descriptor.id, written: aggregateWritten, total: expectedTotal)
            } catch DownloaderError.notFound where Self.optionalFiles.contains(filename) {
                // Expected — optional file, just move on without erroring.
                continue
            } catch DownloaderError.cancelled {
                return
            } catch {
                if cancelledBundleIDs.contains(descriptor.id) { return }
                let msg = error.localizedDescription
                await MainActor.run {
                    states[descriptor.id]?.status = .failed
                    states[descriptor.id]?.failureMessage = msg
                }
                return
            }
        }

        await MainActor.run {
            states[descriptor.id]?.status = .completed
            states[descriptor.id]?.progress = 1.0
            manager.scan()
            NotificationCenter.default.post(name: .mlxBundlesDidChange, object: nil)
        }
    }

    /// Download a single file with a native `URLSessionDownloadTask`. The task
    /// handles chunked I/O at the kernel level (writing straight to a temp file)
    /// and emits progress through a delegate — orders of magnitude faster than
    /// iterating `URLSession.bytes(for:)` byte-by-byte for multi-GB files.
    private func downloadFileStreaming(
        bundleID: String,
        url: URL,
        destination: URL,
        aggregateAlreadyWritten: Int64,
        expectedBundleTotal: Int64
    ) async throws -> Int64 {
        let request = URLRequest(url: url)

        let delegate = ProgressDelegate { [weak self] written, total in
            guard let self else { return }
            let aggregate = aggregateAlreadyWritten + written
            let denom = max(expectedBundleTotal, aggregate)
            let progress = denom > 0 ? min(1.0, Double(aggregate) / Double(denom)) : 0
            Task { @MainActor in
                guard var s = self.states[bundleID] else { return }
                s.currentFileBytes = written
                s.currentFileTotal = max(total, 0)
                s.bytesWritten = aggregate
                s.progress = progress
                self.states[bundleID] = s
            }
        }

        let tempURL: URL
        let response: URLResponse
        do {
            (tempURL, response) = try await session.download(for: request, delegate: delegate)
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw DownloaderError.cancelled
        } catch is CancellationError {
            throw DownloaderError.cancelled
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200...299: break
            case 404:
                try? FileManager.default.removeItem(at: tempURL)
                throw DownloaderError.notFound
            default:
                try? FileManager.default.removeItem(at: tempURL)
                throw DownloaderError.httpError(http.statusCode)
            }
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        return size
    }

    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate {
        private let onProgress: (Int64, Int64) -> Void

        init(onProgress: @escaping (Int64, Int64) -> Void) {
            self.onProgress = onProgress
        }

        func urlSession(_ session: URLSession,
                        downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            onProgress(totalBytesWritten, totalBytesExpectedToWrite)
        }

        func urlSession(_ session: URLSession,
                        downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            // Required by protocol; `session.download(for:delegate:)` returns
            // this location as its tempURL, so nothing to do here.
        }
    }

    @MainActor
    private func updateBundleProgress(_ bundleID: String, written: Int64, total: Int64) {
        guard var s = states[bundleID] else { return }
        s.bytesWritten = written
        s.totalBytes = max(total, written)   // expectedSize is approximate
        s.progress = total > 0 ? min(1.0, Double(written) / Double(total)) : 0
        states[bundleID] = s
    }

    private func huggingFaceURL(repo: String, revision: String, filename: String) -> URL {
        // HF's resolve endpoint returns the raw file with redirects we can follow.
        let escaped = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        let escapedRepo = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
        let escapedRev = revision.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? revision
        let raw = "https://huggingface.co/\(escapedRepo)/resolve/\(escapedRev)/\(escaped)"
        return URL(string: raw) ?? URL(string: "https://huggingface.co/")!
    }

    enum DownloaderError: Error, LocalizedError {
        case cancelled
        case notFound
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .cancelled:           return "Cancelled"
            case .notFound:            return "File not found on Hugging Face (404)"
            case .httpError(let code): return "Hugging Face returned HTTP \(code)"
            }
        }
    }
}
