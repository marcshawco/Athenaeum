import Foundation

// MARK: - MLX Bundle Downloader
//
// Downloads the multi-file Hugging Face snapshot for a single MLXBundleDescriptor
// into its on-disk directory. Files are fetched serially with a single shared
// URLSession; aggregate progress sums bytes across all files.
//
// We deliberately keep this independent of `ModelDownloader` (which is keyed
// by LLMRole + assumes one file per model). MLX bundles aren't role-keyed and
// span multiple files, so a separate downloader keeps each side clean.

@Observable
final class MLXBundleDownloader {
    /// Active download state per bundle id. Absent = idle.
    private(set) var states: [String: BundleDownloadState] = [:]

    private var tasks: [String: URLSessionDataTask] = [:]
    private var cancelledBundleIDs: Set<String> = []

    private let manager: MLXModelManager
    private var session: URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 3600
        return URLSession(configuration: cfg)
    }

    init(manager: MLXModelManager) {
        self.manager = manager
    }

    struct BundleDownloadState: Sendable {
        var status: Status
        var progress: Double          // 0...1
        var bytesWritten: Int64
        var totalBytes: Int64
        var currentFile: String       // most recent file being fetched
        var failureMessage: String?

        enum Status: String, Sendable {
            case downloading, completed, failed, cancelled
        }
    }

    // MARK: - Public API

    func startDownload(_ descriptor: MLXBundleDescriptor) {
        guard tasks[descriptor.id] == nil else { return }
        cancelledBundleIDs.remove(descriptor.id)
        states[descriptor.id] = BundleDownloadState(
            status: .downloading,
            progress: 0,
            bytesWritten: 0,
            totalBytes: descriptor.expectedSize,
            currentFile: descriptor.files.first ?? "",
            failureMessage: nil
        )

        Task.detached(priority: .utility) { [weak self] in
            await self?.runDownload(descriptor)
        }
    }

    func cancelDownload(_ descriptor: MLXBundleDescriptor) {
        cancelledBundleIDs.insert(descriptor.id)
        tasks[descriptor.id]?.cancel()
        tasks[descriptor.id] = nil
        states[descriptor.id]?.status = .cancelled
    }

    func clearFinishedState(_ descriptor: MLXBundleDescriptor) {
        states.removeValue(forKey: descriptor.id)
    }

    // MARK: - Driver

    private func runDownload(_ descriptor: MLXBundleDescriptor) async {
        let dir = manager.directory(for: descriptor)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var aggregateWritten: Int64 = 0

        for filename in descriptor.files {
            if cancelledBundleIDs.contains(descriptor.id) { return }

            await MainActor.run {
                states[descriptor.id]?.currentFile = filename
            }

            let url = huggingFaceURL(repo: descriptor.repoID, revision: descriptor.revision, filename: filename)
            let dest = dir.appendingPathComponent(filename)

            // Skip if already complete (lets a partial set resume on retry).
            if FileManager.default.fileExists(atPath: dest.path),
               let size = try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber,
               size.int64Value > 0 {
                aggregateWritten += size.int64Value
                await updateProgress(descriptor.id, written: aggregateWritten, total: descriptor.expectedSize)
                continue
            }

            do {
                let (tempURL, _) = try await session.download(from: url)
                // Atomic move into place.
                if FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: tempURL, to: dest)
                if let size = try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber {
                    aggregateWritten += size.int64Value
                }
                await updateProgress(descriptor.id, written: aggregateWritten, total: descriptor.expectedSize)
            } catch {
                if cancelledBundleIDs.contains(descriptor.id) { return }
                await MainActor.run {
                    states[descriptor.id]?.status = .failed
                    states[descriptor.id]?.failureMessage = error.localizedDescription
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

    @MainActor
    private func updateProgress(_ bundleID: String, written: Int64, total: Int64) {
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
}
