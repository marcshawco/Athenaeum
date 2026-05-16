import SwiftUI
import UniformTypeIdentifiers

struct DocumentDropDelegate: DropDelegate {
    let onDrop: ([URL]) -> Void
    @Binding var isTargeted: Bool

    static let supportedTypes: [UTType] = [
        .fileURL,
        .pdf, .plainText, .rtf, .rtfd,
        .image, .png, .jpeg, .tiff, .heic,
        .audio, .movie, .audiovisualContent,
        .data, // fallback for .docx and others
    ]

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: Self.supportedTypes.map(\.identifier))
    }

    func dropEntered(info: DropInfo) {
        withAnimation(Japandi.Motion.snappy) { isTargeted = true }
    }

    func dropExited(info: DropInfo) {
        withAnimation(Japandi.Motion.snappy) { isTargeted = false }
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false

        // Prefer explicit file-url providers first; fall back to any supported type
        let fileURLProviders = info.itemProviders(for: [UTType.fileURL.identifier])
        let fallbackProviders = fileURLProviders.isEmpty
            ? info.itemProviders(for: Self.supportedTypes.map(\.identifier))
            : []
        let providers = fileURLProviders.isEmpty ? fallbackProviders : fileURLProviders
        guard !providers.isEmpty else { return false }

        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty {
                await MainActor.run { onDrop(urls) }
            }
        }
        return true
    }

    // MARK: - URL Loading

    /// Try multiple strategies to extract a file URL from an NSItemProvider.
    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        // Strategy 1: load as NSURL (most reliable for Finder drags)
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = try? await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<URL, Error>) in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let error { continuation.resume(throwing: error); return }
                    if let url = item as? URL {
                        continuation.resume(returning: url)
                    } else if let data = item as? Data,
                              let str = String(data: data, encoding: .utf8),
                              let url = URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: URLError(.badURL))
                    }
                }
            }) {
                return url
            }
        }

        // Strategy 2: load data representation and write to temp file
        for uti in Self.supportedTypes {
            if provider.hasItemConformingToTypeIdentifier(uti.identifier) {
                let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                    provider.loadDataRepresentation(forTypeIdentifier: uti.identifier) { data, _ in
                        continuation.resume(returning: data)
                    }
                }
                if let data {
                    let ext = uti.preferredFilenameExtension ?? "bin"
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("athenaeum-drop-\(UUID().uuidString)")
                        .appendingPathExtension(ext)
                    do {
                        try data.write(to: tempURL, options: .atomic)
                        return tempURL
                    } catch {
                        return nil
                    }
                }
            }
        }

        return nil
    }
}
