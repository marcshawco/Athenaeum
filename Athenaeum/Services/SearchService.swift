import Foundation
import SwiftData

// MARK: - Search Service

@Observable
final class SearchService {
    var query: String = ""
    var selectedTags: Set<String> = []
    var dateRange: ClosedRange<Date>?
    var sortOrder: SortOrder = .newestFirst

    enum SortOrder: String, CaseIterable, Sendable {
        case newestFirst    = "Date Added · Newest"
        case oldestFirst    = "Date Added · Oldest"
        case docDateNewest  = "Document Date · Newest"
        case docDateOldest  = "Document Date · Oldest"
        case modifiedNewest = "Last Modified · Newest"
        case modifiedOldest = "Last Modified · Oldest"
        case titleAZ        = "Title A-Z"
        case titleZA        = "Title Z-A"

        var sortDescriptor: SortDescriptor<Document> {
            switch self {
            case .newestFirst:    SortDescriptor(\.importedAt,  order: .reverse)
            case .oldestFirst:    SortDescriptor(\.importedAt,  order: .forward)
            case .docDateNewest:  SortDescriptor(\.documentDate, order: .reverse)
            case .docDateOldest:  SortDescriptor(\.documentDate, order: .forward)
            case .modifiedNewest: SortDescriptor(\.modifiedAt,  order: .reverse)
            case .modifiedOldest: SortDescriptor(\.modifiedAt,  order: .forward)
            case .titleAZ:        SortDescriptor(\.title,       order: .forward)
            case .titleZA:        SortDescriptor(\.title,       order: .reverse)
            }
        }
    }

    /// Apply all active filters (text, tags, dates) to a document array.
    func filter(_ documents: [Document]) -> [Document] {
        var results = documents

        // Text search
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !trimmed.isEmpty {
            results = results.filter { doc in
                doc.searchableText?.localizedCaseInsensitiveContains(trimmed) == true
                || doc.title.localizedCaseInsensitiveContains(trimmed)
                || doc.originalFilename.localizedCaseInsensitiveContains(trimmed)
            }
        }

        // Tag filter
        if !selectedTags.isEmpty {
            results = results.filter { doc in
                guard let tags = doc.tags, !tags.isEmpty else { return false }
                let docTagNames = Set(tags.map(\.name))
                return selectedTags.isSubset(of: docTagNames)
            }
        }

        // Date range filter
        if let dateRange {
            results = results.filter { doc in
                let date = doc.documentDate ?? doc.importedAt
                return dateRange.contains(date)
            }
        }

        // Sort
        switch sortOrder {
        case .newestFirst:    results.sort { $0.importedAt > $1.importedAt }
        case .oldestFirst:    results.sort { $0.importedAt < $1.importedAt }
        case .docDateNewest:
            // Documents without a parsed date sink to the bottom of the
            // sort so they don't dominate the "newest" view.
            results.sort { ($0.documentDate ?? .distantPast) > ($1.documentDate ?? .distantPast) }
        case .docDateOldest:
            results.sort { ($0.documentDate ?? .distantFuture) < ($1.documentDate ?? .distantFuture) }
        case .modifiedNewest: results.sort { $0.modifiedAt > $1.modifiedAt }
        case .modifiedOldest: results.sort { $0.modifiedAt < $1.modifiedAt }
        case .titleAZ:        results.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .titleZA:        results.sort { $0.title.localizedCompare($1.title) == .orderedDescending }
        }

        return results
    }

    /// Filter documents by sidebar section.
    func filterBySection(_ documents: [Document], section: SidebarSection) -> [Document] {
        switch section {
        case .all:
            return documents
        case .recent:
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
            return documents.filter { $0.importedAt >= cutoff }
        case .processing:
            return documents.filter {
                $0.processingStatus != .complete && $0.processingStatus != .failed
            }
        case .untagged:
            return documents.filter { $0.tags == nil || $0.tags?.isEmpty == true }
        case .tag(let tagName):
            return documents.filter { doc in
                doc.tags?.contains(where: { $0.name == tagName }) == true
            }
        case .category(let slug):
            return documents.filter { $0.categorySlug == slug }
        case .folder(let id):
            return documents.filter { doc in
                doc.folders?.contains(where: { $0.id == id }) == true
            }
        case .chat, .models:
            return documents
        }
    }

    var hasActiveFilters: Bool {
        !query.isEmpty || !selectedTags.isEmpty || dateRange != nil
    }

    func reset() {
        query = ""
        selectedTags.removeAll()
        dateRange = nil
        sortOrder = .newestFirst
    }
}
