import Foundation
import SwiftData
import AppKit

// MARK: - Export Service
// Handles exporting documents in various formats.

enum ExportFormat: String, CaseIterable, Sendable {
    case original   = "Original File"
    case text       = "Plain Text (.txt)"
    case json       = "JSON Metadata"
    case csv        = "CSV Catalog"
}

@Observable
final class ExportService {
    private(set) var isExporting = false
    private(set) var exportProgress: Double = 0

    // MARK: - Export Single Document

    func exportDocument(_ document: Document, format: ExportFormat, to url: URL) throws {
        switch format {
        case .original:
            guard let data = originalData(for: document) else {
                throw ExportError.noFileData
            }
            try data.write(to: url)

        case .text:
            let text = document.extractedText ?? "No text extracted"
            try text.write(to: url, atomically: true, encoding: .utf8)

        case .json:
            let metadata = DocumentMetadataExport(
                title: document.title,
                originalFilename: document.originalFilename,
                fileType: document.fileType,
                fileSize: document.fileSize,
                tags: document.tags?.map(\.name) ?? [],
                correspondent: document.correspondent,
                documentDate: document.documentDate?.ISO8601Format(),
                importedAt: document.importedAt.ISO8601Format(),
                summary: document.summary
            )
            let data = try JSONEncoder.prettyPrinted.encode(metadata)
            try data.write(to: url)

        case .csv:
            // Single document as CSV row
            let csv = csvHeader + "\n" + csvRow(for: document)
            try csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Export Multiple Documents

    func exportCatalog(documents: [Document], to url: URL) throws {
        isExporting = true
        defer { isExporting = false }

        var csv = csvHeader + "\n"
        for (index, doc) in documents.enumerated() {
            exportProgress = Double(index) / Double(documents.count)
            csv += csvRow(for: doc) + "\n"
        }
        exportProgress = 1.0
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - CSV Helpers

    private var csvHeader: String {
        "Title,Filename,Type,Size,Tags,Correspondent,Document Date,Imported At,Status"
    }

    private func csvRow(for doc: Document) -> String {
        let tags = doc.tags?.map(\.name).joined(separator: "; ") ?? ""
        let docDate = doc.documentDate?.formatted(date: .abbreviated, time: .omitted) ?? ""
        let imported = doc.importedAt.formatted(date: .abbreviated, time: .omitted)

        return [
            csvEscape(doc.title),
            csvEscape(doc.originalFilename),
            doc.fileExtension.uppercased(),
            doc.fileSizeFormatted,
            csvEscape(tags),
            csvEscape(doc.correspondent ?? ""),
            docDate,
            imported,
            doc.processingStatus.rawValue
        ].joined(separator: ",")
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private func originalData(for document: Document) -> Data? {
        if let url = document.storedFileURL,
           FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url) {
            return data
        }
        return document.fileData
    }
}

// MARK: - Export Dialog

extension ExportService {
    @MainActor
    static func showExportPanel(suggestedName: String, allowedTypes: [String] = ["csv", "json", "txt"]) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func showDirectoryPicker() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - Export Metadata Model

struct DocumentMetadataExport: Codable {
    let title: String
    let originalFilename: String
    let fileType: String
    let fileSize: Int64
    let tags: [String]
    let correspondent: String?
    let documentDate: String?
    let importedAt: String
    let summary: String?
}

// MARK: - JSON Encoder Extension

extension JSONEncoder {
    // Computed to avoid Swift 6 @MainActor inference on static stored properties
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

// MARK: - Errors

enum ExportError: LocalizedError {
    case noFileData
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noFileData: "Document has no file data to export."
        case .exportFailed(let msg): "Export failed: \(msg)"
        }
    }
}
