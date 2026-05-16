import Foundation
import PDFKit
import UniformTypeIdentifiers
import AVFoundation

struct ExtractedDocumentMetadata: Sendable {
    var title: String?
    var correspondent: String?
    var subject: String?
    var keywords: [String] = []
    var creationDate: Date?
    var modificationDate: Date?
    var documentDate: Date?
    var documentDateSource: String?
}

struct DocumentClassification: Codable, Sendable {
    var title: String?
    var tags: [String]
    var correspondent: String?
    var date: String?
    var summary: String?
    /// Slug from the canonical 500-type taxonomy (see `DocumentTaxonomy`).
    var documentType: String?
    /// Slug of the parent taxonomy category.
    var category: String?

    enum CodingKeys: String, CodingKey {
        case title, tags, correspondent, date, summary
        case documentType = "document_type"
        case category
    }

    init(
        title: String? = nil,
        tags: [String] = [],
        correspondent: String? = nil,
        date: String? = nil,
        summary: String? = nil,
        documentType: String? = nil,
        category: String? = nil
    ) {
        self.title = title
        self.tags = tags
        self.correspondent = correspondent
        self.date = date
        self.summary = summary
        self.documentType = documentType
        self.category = category
    }
}

// MARK: - Metadata Extraction

/// Pulls archival metadata before the LLM pass so imported documents remain useful
/// even when local models are still downloading or unavailable.
final class DocumentMetadataExtractor: Sendable {
    func extractInitialMetadata(from url: URL, data: Data, uti: String) async -> ExtractedDocumentMetadata {
        var metadata = ExtractedDocumentMetadata()

        if let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) {
            metadata.creationDate = values.creationDate
            metadata.modificationDate = values.contentModificationDate
        }

        if UTType(uti)?.conforms(to: .pdf) == true {
            mergePDFMetadata(from: data, into: &metadata)
        }

        if isAudioVisual(url: url, uti: uti) {
            await mergeAVMetadata(from: url, into: &metadata)
        }

        if metadata.documentDate == nil {
            metadata.documentDate = metadata.creationDate ?? metadata.modificationDate
            metadata.documentDateSource = metadata.documentDate == nil ? nil : "file metadata"
        }

        return metadata
    }

    func refineMetadata(_ metadata: ExtractedDocumentMetadata, withText text: String) -> ExtractedDocumentMetadata {
        var refined = metadata

        if refined.documentDate == nil, let parsedDate = Self.firstLikelyDate(in: text) {
            refined.documentDate = parsedDate
            refined.documentDateSource = "document text"
        }

        if refined.correspondent == nil {
            refined.correspondent = Self.firstMatch(
                in: text,
                pattern: #"(?im)^(?:from|author|correspondent|vendor|sender):\s*(.+)$"#
            )
        }

        return refined
    }

    // MARK: - PDF

    private func mergePDFMetadata(from data: Data, into metadata: inout ExtractedDocumentMetadata) {
        guard let pdf = PDFDocument(data: data),
              let attributes = pdf.documentAttributes else { return }

        metadata.title = attributes[PDFDocumentAttribute.titleAttribute] as? String
        metadata.correspondent = attributes[PDFDocumentAttribute.authorAttribute] as? String
        metadata.subject = attributes[PDFDocumentAttribute.subjectAttribute] as? String
        metadata.creationDate = (attributes[PDFDocumentAttribute.creationDateAttribute] as? Date) ?? metadata.creationDate
        metadata.modificationDate = (attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date) ?? metadata.modificationDate

        if let keywords = attributes[PDFDocumentAttribute.keywordsAttribute] as? [String] {
            metadata.keywords.append(contentsOf: keywords)
        } else if let keywordString = attributes[PDFDocumentAttribute.keywordsAttribute] as? String {
            metadata.keywords.append(contentsOf: keywordString.components(separatedBy: CharacterSet(charactersIn: ",;")))
        }

        if metadata.documentDate == nil {
            metadata.documentDate = metadata.creationDate ?? metadata.modificationDate
            metadata.documentDateSource = metadata.documentDate == nil ? nil : "PDF metadata"
        }
    }

    // MARK: - AVFoundation

    private func isAudioVisual(url: URL, uti: String) -> Bool {
        guard let type = UTType(uti) else {
            return ["mp3", "m4a", "wav", "mov", "mp4", "m4v"].contains(url.pathExtension.lowercased())
        }
        return type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .audiovisualContent)
    }

    private func mergeAVMetadata(from url: URL, into metadata: inout ExtractedDocumentMetadata) async {
        let asset = AVURLAsset(url: url)

        guard let commonMetadata = try? await asset.load(.commonMetadata) else { return }

        for item in commonMetadata {
            guard let key = item.commonKey?.rawValue else { continue }
            let value = try? await item.load(.stringValue)

            switch key {
            case AVMetadataKey.commonKeyTitle.rawValue where metadata.title == nil:
                metadata.title = value
            case AVMetadataKey.commonKeyArtist.rawValue where metadata.correspondent == nil:
                metadata.correspondent = value
            case AVMetadataKey.commonKeyDescription.rawValue where metadata.subject == nil:
                metadata.subject = value
            case AVMetadataKey.commonKeyCreationDate.rawValue where metadata.documentDate == nil:
                if let value, let date = Self.parseDate(value) {
                    metadata.documentDate = date
                    metadata.documentDateSource = "media metadata"
                }
            default:
                break
            }
        }
    }

    // MARK: - Date Parsing

    static func firstLikelyDate(in text: String) -> Date? {
        let sample = String(text.prefix(12_000))
        let patterns = [
            #"\b\d{4}-\d{2}-\d{2}\b"#,
            #"\b\d{1,2}/\d{1,2}/\d{2,4}\b"#,
            #"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4}\b"#,
            #"\b\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+\d{4}\b"#
        ]

        for pattern in patterns {
            guard let match = firstMatch(in: sample, pattern: pattern),
                  let date = parseDate(match),
                  isReasonableDocumentDate(date) else { continue }
            return date
        }

        return nil
    }

    static func parseDate(_ string: String) -> Date? {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        if let date = iso.date(from: value) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in ["M/d/yyyy", "MM/dd/yyyy", "M/d/yy", "MMM d, yyyy", "MMMM d, yyyy", "d MMM yyyy", "d MMMM yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }

        return nil
    }

    private static func isReasonableDocumentDate(_ date: Date) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        let lower = calendar.date(from: DateComponents(year: 1980, month: 1, day: 1)) ?? .distantPast
        let upper = calendar.date(byAdding: .year, value: 1, to: .now) ?? .distantFuture
        return date >= lower && date <= upper
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
        guard let swiftRange = Range(captureRange, in: text) else { return nil }
        return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Offline Classification

enum OfflineDocumentClassifier {
    static func classify(text: String, filename: String, metadata: ExtractedDocumentMetadata) -> DocumentClassification {
        let lower = "\(filename) \(metadata.subject ?? "") \(text.prefix(5000))".lowercased()
        var tags = Set<String>()

        let keywordTags: [(String, [String])] = [
            ("invoice", ["invoice", "amount due", "bill to", "payment terms"]),
            ("receipt", ["receipt", "subtotal", "total paid", "merchant"]),
            ("bill", ["bill", "statement due", "minimum payment", "utility"]),
            ("quote", ["quote", "quotation", "estimate valid", "proposal amount"]),
            ("purchase-order", ["purchase order", "po number", "p.o. number"]),
            ("tax", ["tax", "irs", "w-2", "1099", "deduction"]),
            ("payroll", ["payroll", "gross pay", "net pay", "employee earnings"]),
            ("paystub", ["paystub", "pay statement", "earnings statement"]),
            ("contract", ["agreement", "contract", "terms and conditions", "signature"]),
            ("statement-of-work", ["statement of work", "scope of work", "deliverables"]),
            ("finance", ["bank", "statement", "account number", "transaction"]),
            ("bank-statement", ["bank statement", "ending balance", "deposits", "withdrawals"]),
            ("credit-card", ["credit card", "card ending", "minimum payment due"]),
            ("insurance", ["insurance", "premium", "policy number", "claim"]),
            ("medical", ["patient", "diagnosis", "clinic", "prescription"]),
            ("lab-results", ["lab results", "reference range", "specimen", "test result"]),
            ("legal", ["court", "attorney", "plaintiff", "defendant"]),
            ("lease", ["lease", "tenant", "landlord", "rent"]),
            ("research", ["abstract", "references", "methodology", "doi"]),
            ("travel", ["itinerary", "boarding", "reservation", "confirmation"]),
            ("vehicle", ["vehicle", "vin", "registration", "odometer"]),
            ("warranty", ["warranty", "serial number", "coverage period"]),
            ("education", ["transcript", "course", "tuition", "student"]),
            ("identity", ["passport", "driver license", "social security", "date of birth"]),
            ("correspondence", ["dear ", "sincerely", "regards", "from:"])
        ]

        for (tag, needles) in keywordTags where needles.contains(where: { lower.contains($0) }) {
            tags.insert(tag)
        }

        for keyword in metadata.keywords {
            let normalized = normalizeTag(keyword)
            if !normalized.isEmpty { tags.insert(normalized) }
        }

        let summary = firstSummarySentence(from: text, fallback: metadata.subject)
        let date = metadata.documentDate.map { isoDateString($0) }

        if tags.count == 1 {
            tags.insert("to-review")
        }

        return DocumentClassification(
            title: metadata.title,
            tags: Array(tags).sorted(),
            correspondent: metadata.correspondent,
            date: date,
            summary: summary
        )
    }

    private static func firstSummarySentence(from text: String, fallback: String?) -> String? {
        let cleaned = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !cleaned.isEmpty else { return fallback }
        let separators = CharacterSet(charactersIn: ".!?")
        let sentence = cleaned.components(separatedBy: separators).first ?? cleaned
        let clipped = String(sentence.prefix(240)).trimmingCharacters(in: .whitespacesAndNewlines)
        return clipped.isEmpty ? fallback : clipped
    }

    private static func normalizeTag(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(3)
            .joined(separator: "-")
    }

    private static func isoDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
