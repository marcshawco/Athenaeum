import Foundation

// MARK: - MLX Bundle Downloader
//
// Downloads the multi-file Hugging Face snapshot for a single MLXBundleDescriptor
// into its on-disk directory. Files are fetched serially, each one streamed
// chunk-by-chunk so the progress bar moves smoothly even on a 4 GB safetensors
// file.
//
// We deliberately keep this independent of `ModelDownloader` (which is keyed
// by LLMRole + assumes one file per model). MLX bundles aren't role-keyed and
// span multiple files, so a separate downloader keeps each side clean.

@Observable
final class MLXBundleDownloader {
    /// Active download state per bundle id. Absent = idle.
    private(set) var states: [String: BundleDownloadState] = [:]

    private var cancelledBundleIDs: Set<String> = []

    private let manager: MLXModelManager

    /// One shared `URLSession` for the lifetime of this downloader. Allocating
    /// a new session per file (the old computed-property bug) loses connection
    /// reuse and made cancellation unreliable.
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 7200
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Athenaeum/1.0 (+local)"
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

        Task.detached(priority: .utility) { [weak self] in
            await self?.runDownload(descriptor)
        }
    }

    func cancelDownload(_ descriptor: MLXBundleDescriptor) {
        cancelledBundleIDs.insert(descriptor.id)
        states[descriptor.id]?.status = .cancelled
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
                await updateBundleProgress(descriptor.id, written: aggregateWritten, total: expectedTotal)
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
                await updateBundleProgress(descriptor.id, written: aggregateWritten, total: expectedTotal)
            } catch let DownloaderError.notFound where Self.optionalFiles.contains(filename) {
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

    /// Stream a single file using `URLSession.bytes(for:)`. Writes to a
    /// `.partial` file as bytes arrive and atomically renames on completion.
    /// Returns the total bytes written for this file.
    private func downloadFileStreaming(
        bundleID: String,
        url: URL,
        destination: URL,
        aggregateAlreadyWritten: Int64,
        expectedBundleTotal: Int64
    ) async throws -> Int64 {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (stream, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (stream, response) = try await session.bytes(for: request)
        } catch {
            throw error
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200...299: break
            case 404:       throw DownloaderError.notFound
            default:        throw DownloaderError.httpError(http.statusCode)
            }
        }

        let totalForFile = response.expectedContentLength
        await MainActor.run {
            states[bundleID]?.currentFileTotal = max(totalForFile, 0)
        }

        // Stream into a .partial sibling and rename at the end.
        let partial = destination.appendingPathExtension("partial")
        if FileManager.default.fileExists(atPath: partial.path) {
            try? FileManager.default.removeItem(at: partial)
        }
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }

        var buffer = Data()
        var fileBytes: Int64 = 0
        let flushThreshold = 256 * 1024   // 256 KB per flush — cheap I/O
        let uiUpdateThreshold: Int64 = 512 * 1024

        var bytesSinceUIUpdate: Int64 = 0

        for try await byte in stream {
            if cancelledBundleIDs.contains(bundleID) {
                try? FileManager.default.removeItem(at: partial)
                throw DownloaderError.cancelled
            }
            buffer.append(byte)
            fileBytes += 1
            bytesSinceUIUpdate += 1

            if buffer.count >= flushThreshold {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }

            if bytesSinceUIUpdate >= uiUpdateThreshold {
                let snapshotFileBytes = fileBytes
                let snapshotAggregate = aggregateAlreadyWritten + fileBytes
                await MainActor.run {
                    states[bundleID]?.currentFileBytes = snapshotFileBytes
                    states[bundleID]?.bytesWritten = snapshotAggregate
                    let total = max(expectedBundleTotal, snapshotAggregate)
                    states[bundleID]?.progress = total > 0
                        ? min(1.0, Double(snapshotAggregate) / Double(total))
                        : 0
                }
                bytesSinceUIUpdate = 0
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)
        }
        try handle.close()

        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: partial, to: destination)
        return fileBytes
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
