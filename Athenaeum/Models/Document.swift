import Foundation
import SwiftData

@Model
final class Document {
    // MARK: - Identity
    var id: UUID
    var title: String
    var originalFilename: String

    // MARK: - Content
    var fileType: String                   // UTType identifier string
    var fileSize: Int64                     // bytes
    var storagePath: String?                // Finder-visible vault location for the original file
    @Attribute(.externalStorage)
    var fileData: Data?                    // raw file stored externally by SwiftData

    // MARK: - Extracted Content
    @Attribute(.externalStorage)
    var extractedText: String?             // OCR / parsed text
    var summary: String?                   // LLM-generated summary

    // MARK: - Organization
    @Relationship(inverse: \Tag.documents)
    var tags: [Tag]?

    var correspondent: String?             // who sent / authored
    var documentDate: Date?                // date from the document itself
    var importedAt: Date
    var modifiedAt: Date

    // MARK: - Taxonomy (Top-500 reference)
    /// Slug from `DocumentTaxonomy.allTypeSlugs` — e.g. "lease-agreement", "irs-form-1040".
    /// Lets us render a precise "Lease Agreement" pill instead of a generic "contract" tag.
    var documentTypeSlug: String?
    /// Slug from `DocumentTaxonomy.allCategorySlugs` — e.g. "real-estate-property-documents".
    var categorySlug: String?

    // MARK: - Processing State
    var processingStatus: ProcessingStatus
    var processingError: String?

    // MARK: - Search
    var searchableText: String?            // combined index: title + tags + extracted text

    init(
        title: String,
        originalFilename: String,
        fileType: String,
        fileSize: Int64,
        fileData: Data? = nil,
        documentDate: Date? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.originalFilename = originalFilename
        self.fileType = fileType
        self.fileSize = fileSize
        self.storagePath = nil
        self.fileData = fileData
        self.documentDate = documentDate
        self.importedAt = .now
        self.modifiedAt = .now
        self.processingStatus = .pending
        self.processingError = nil
    }

    func rebuildSearchableText() {
        var parts: [String] = [title, originalFilename]
        if let tags { parts.append(contentsOf: tags.map(\.name)) }
        if let extractedText { parts.append(extractedText) }
        if let correspondent { parts.append(correspondent) }
        if let summary { parts.append(summary) }
        if let processingError { parts.append(processingError) }
        // Index taxonomy facets so searching "lease agreement" or
        // "real estate" finds documents that match by category/type even
        // when those words don't appear in the body or tag list.
        if let documentTypeSlug { parts.append(documentTypeSlug.replacingOccurrences(of: "-", with: " ")) }
        if let documentTypeName { parts.append(documentTypeName) }
        if let categoryName { parts.append(categoryName) }
        searchableText = parts.joined(separator: " ").lowercased()
    }
}

// MARK: - Processing Status

enum ProcessingStatus: String, Codable, Sendable {
    case pending
    case extractingText
    case analyzingContent
    case tagging
    case complete
    case failed
}

// MARK: - Convenience

extension Document {
    /// Resolved display name for the taxonomy type — e.g. "Lease Agreement".
    var documentTypeName: String? {
        documentTypeSlug.flatMap { DocumentTaxonomy.type(forSlug: $0)?.name }
    }

    /// Resolved display name for the taxonomy category — e.g. "Real Estate & Property Documents".
    var categoryName: String? {
        categorySlug.flatMap { DocumentTaxonomy.category(forSlug: $0)?.name }
    }

    /// Short purpose blurb for the resolved type (from the reference guide).
    var documentTypePurpose: String? {
        documentTypeSlug.flatMap { DocumentTaxonomy.type(forSlug: $0)?.purpose }
    }

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var fileExtension: String {
        (originalFilename as NSString).pathExtension.lowercased()
    }

    var isPDF: Bool { fileExtension == "pdf" }
    var isImage: Bool { ["png", "jpg", "jpeg", "tif", "tiff", "heic", "webp", "gif", "bmp"].contains(fileExtension) }

    var storedFileURL: URL? {
        guard let storagePath, !storagePath.isEmpty else { return nil }
        return URL(fileURLWithPath: storagePath)
    }
}
