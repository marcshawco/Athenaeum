import Foundation
import SwiftData

// MARK: - Batch Processor
// Handles bulk operations on document selections.

@Observable
final class BatchProcessor {
    private let modelContext: ModelContext
    private(set) var isProcessing = false
    private(set) var progress: Double = 0
    private(set) var currentOperation: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Batch Tag

    /// Add a tag to multiple documents.
    func addTag(_ tagName: String, to documents: [Document]) {
        guard !documents.isEmpty else { return }
        isProcessing = true
        currentOperation = "Adding tag..."
        defer { isProcessing = false; currentOperation = nil }

        let normalized = normalizeTagName(tagName)
        guard !normalized.isEmpty else { return }

        // Find or create tag
        let predicate = #Predicate<Tag> { $0.name == normalized }
        let descriptor = FetchDescriptor<Tag>(predicate: predicate)
        let existing = try? modelContext.fetch(descriptor).first

        let tag = existing ?? Tag(name: normalized, colorHex: Tag.defaultColors.randomElement() ?? "2A639D")
        if existing == nil {
            modelContext.insert(tag)
        }

        for (index, doc) in documents.enumerated() {
            progress = Double(index) / Double(documents.count)
            if doc.tags == nil { doc.tags = [] }
            if !(doc.tags?.contains(where: { $0.name == normalized }) ?? false) {
                doc.tags?.append(tag)
                doc.modifiedAt = .now
                doc.rebuildSearchableText()
            }
        }

        try? modelContext.save()
        progress = 1.0
    }

    /// Remove a tag from multiple documents.
    func removeTag(_ tagName: String, from documents: [Document]) {
        guard !documents.isEmpty else { return }
        isProcessing = true
        currentOperation = "Removing tag..."
        defer { isProcessing = false; currentOperation = nil }

        let normalized = normalizeTagName(tagName)
        guard !normalized.isEmpty else { return }

        for (index, doc) in documents.enumerated() {
            progress = Double(index) / Double(documents.count)
            let originalCount = doc.tags?.count ?? 0
            doc.tags?.removeAll { $0.name == normalized }
            if (doc.tags?.count ?? 0) != originalCount {
                doc.modifiedAt = .now
            }
            doc.rebuildSearchableText()
        }

        try? modelContext.save()
        progress = 1.0
    }

    // MARK: - Batch Delete

    func deleteDocuments(_ documents: [Document]) {
        guard !documents.isEmpty else { return }
        isProcessing = true
        currentOperation = "Deleting..."
        defer { isProcessing = false; currentOperation = nil }

        let deletedIDs = documents.map(\.id)
        for (index, doc) in documents.enumerated() {
            progress = Double(index) / Double(documents.count)
            if let url = doc.storedFileURL, FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            modelContext.delete(doc)
        }

        try? modelContext.save()
        NotificationCenter.default.post(
            name: .documentsDeleted,
            object: nil,
            userInfo: ["documentIDs": deletedIDs]
        )
        progress = 1.0
    }

    // MARK: - Batch Export

    func exportDocuments(_ documents: [Document], to directory: URL) {
        guard !documents.isEmpty else { return }
        isProcessing = true
        currentOperation = "Exporting..."
        defer { isProcessing = false; currentOperation = nil }

        for (index, doc) in documents.enumerated() {
            progress = Double(index) / Double(documents.count)

            let storedData = doc.storedFileURL.flatMap { try? Data(contentsOf: $0) }
            guard let data = storedData ?? doc.fileData else { continue }

            // `originalFilename` is user-editable through later flows;
            // strip any directory components so a name like
            // "../../Library/foo.txt" can't escape the chosen export
            // directory. The destination is sandbox-allowed (the user
            // just picked it), so the kernel won't catch this for us.
            let safeName = (doc.originalFilename as NSString).lastPathComponent
            let resolvedName = safeName.isEmpty ? "document" : safeName
            let destination = directory.appendingPathComponent(resolvedName)

            // Handle name collisions
            var finalURL = destination
            var counter = 1
            while FileManager.default.fileExists(atPath: finalURL.path) {
                let name = destination.deletingPathExtension().lastPathComponent
                let ext = destination.pathExtension
                finalURL = directory
                    .appendingPathComponent("\(name) (\(counter))")
                    .appendingPathExtension(ext)
                counter += 1
            }

            try? data.write(to: finalURL)
        }

        progress = 1.0
    }

    // MARK: - Batch Reprocess

    func reprocessDocuments(_ documents: [Document]) {
        guard !documents.isEmpty else { return }
        isProcessing = true
        currentOperation = "Queuing reprocess..."
        defer { isProcessing = false; currentOperation = nil }

        for (index, doc) in documents.enumerated() {
            progress = Double(index) / Double(documents.count)
            doc.processingStatus = .pending
            doc.processingError = nil
            doc.extractedText = nil
            doc.summary = nil
            doc.modifiedAt = .now
            doc.rebuildSearchableText()
        }

        try? modelContext.save()
        progress = 1.0
    }

    private func normalizeTagName(_ rawName: String) -> String {
        rawName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: "-")
    }
}
