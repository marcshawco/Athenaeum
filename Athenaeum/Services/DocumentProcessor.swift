import Foundation
import SwiftData
import PDFKit
import UniformTypeIdentifiers
import AppKit

// MARK: - Document Processor

/// Orchestrates the document import pipeline:
/// 1. Read file → 2. Extract text (OCR if needed) → 3. Classify & tag via LLM → 4. Persist → 5. Index for RAG
@Observable
final class DocumentProcessor {
    private let llmService: LLMServiceProtocol
    private let ragService: RAGService?
    private let modelContext: ModelContext
    private let ocrService = VisionOCRService()
    private let metadataExtractor = DocumentMetadataExtractor()
    private let vaultService: DocumentVaultService

    private(set) var isProcessing = false
    private(set) var processingQueue: [URL] = []
    private(set) var currentFile: String?
    private(set) var error: String?

    /// Threshold: if a PDF has fewer than this many characters per page, treat as scanned.
    private let scannedPDFThreshold = 50

    init(
        llmService: LLMServiceProtocol,
        ragService: RAGService? = nil,
        modelContext: ModelContext,
        vaultService: DocumentVaultService = .shared
    ) {
        self.llmService = llmService
        self.ragService = ragService
        self.modelContext = modelContext
        self.vaultService = vaultService
    }

    // MARK: - Public API

    /// Import one or more files. Accepts file URLs from drag-drop or file picker.
    @discardableResult
    func importFiles(_ urls: [URL]) async -> Int {
        error = nil
        var storedURLs: [URL] = []

        for url in urls {
            defer { cleanupTemporaryImportFileIfNeeded(url) }
            guard !documentAlreadyExists(for: url) else { continue }
            do {
                if vaultService.isInVault(url) {
                    storedURLs.append(url)
                } else {
                    storedURLs.append(try vaultService.storeExternalFile(url))
                }
            } catch {
                self.error = "Failed to store \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }

        processingQueue.append(contentsOf: storedURLs)
        guard !isProcessing else { return storedURLs.count }
        isProcessing = true
        defer { isProcessing = false; currentFile = nil }

        while let url = processingQueue.first {
            processingQueue.removeFirst()
            currentFile = url.lastPathComponent
            do {
                try await processFile(at: url)
            } catch {
                self.error = "Failed to process \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }

        return storedURLs.count
    }

    /// Scan the user-visible vault for files placed there from Finder.
    func scanVaultForNewDocuments() async -> Int {
        error = nil
        do {
            let urls = try vaultService.scanForDocuments()
            let newURLs = urls.filter { !documentAlreadyExists(for: $0) }
            return await importFiles(newURLs)
        } catch {
            self.error = "Failed to scan document vault: \(error.localizedDescription)"
            return 0
        }
    }

    /// Re-run the full extraction + tagging pipeline for documents already in the store.
    /// If the processor is busy, the documents are queued and will run after the current batch.
    func reprocessDocuments(_ documents: [Document]) async {
        guard !documents.isEmpty else { return }

        // Mark all as pending immediately so sidebar badge updates
        for doc in documents where doc.processingStatus == .complete || doc.processingStatus == .failed {
            doc.processingStatus = .pending
        }

        while isProcessing {
            try? await Task.sleep(for: .milliseconds(250))
        }

        isProcessing = true
        defer { isProcessing = false; currentFile = nil }

        for document in documents {
            currentFile = document.originalFilename
            do {
                try await reprocessStoredDocument(document)
            } catch {
                self.error = "Failed to reprocess \(document.originalFilename): \(error.localizedDescription)"
            }
        }
    }

    private func reprocessStoredDocument(_ document: Document) async throws {
        let storedURL = document.storedFileURL
        let storedData = storedURL.flatMap { try? Data(contentsOf: $0) }
        guard let fileData = storedData ?? document.fileData else {
            document.processingStatus = .failed
            document.processingError = "Original file data is missing."
            document.modifiedAt = .now
            document.rebuildSearchableText()
            try? modelContext.save()
            return
        }
        let uti = document.fileType

        do {
            // Reset state
            document.processingStatus = .extractingText
            document.processingError = nil
            document.extractedText = nil
            document.summary = nil
            document.tags?.removeAll()

            let tempURL: URL
            let shouldRemoveTemp: Bool
            if let storedURL, FileManager.default.fileExists(atPath: storedURL.path) {
                tempURL = storedURL
                shouldRemoveTemp = false
            } else {
                // Write data to a unique temp URL so concurrent reprocesses don't collide
                tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("athenaeum-reprocess-\(document.id.uuidString)")
                    .appendingPathExtension(document.fileExtension)
                try fileData.write(to: tempURL)
                shouldRemoveTemp = true
            }
            defer { if shouldRemoveTemp { try? FileManager.default.removeItem(at: tempURL) } }

            let extractedText = try await extractText(from: tempURL, data: fileData, uti: uti)
            document.extractedText = extractedText
            let initialMetadata = await metadataExtractor.extractInitialMetadata(from: tempURL, data: fileData, uti: uti)
            let refinedMetadata = metadataExtractor.refineMetadata(initialMetadata, withText: extractedText)
            applyMetadata(refinedMetadata, to: document)

            if !extractedText.isEmpty {
                document.processingStatus = .tagging
                await classifyAndTag(document: document, text: extractedText, metadata: refinedMetadata)
            } else {
                let fallback = OfflineDocumentClassifier.classify(
                    text: "",
                    filename: document.originalFilename,
                    metadata: refinedMetadata
                )
                applyClassification(fallback, to: document)
            }

            document.processingStatus = .complete
            document.modifiedAt = .now
            document.rebuildSearchableText()
            try modelContext.save()

            // Re-index for RAG after reprocessing
            if !extractedText.isEmpty, let ragService {
                try? await ragService.indexDocument(id: document.id, text: extractedText)
            }
        } catch {
            document.processingStatus = .failed
            document.processingError = error.localizedDescription
            document.modifiedAt = .now
            document.rebuildSearchableText()
            try? modelContext.save()
            throw error
        }
    }

    // MARK: - Pipeline

    private func processFile(at url: URL) async throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard !documentAlreadyExists(for: url) else { return }

        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .typeIdentifierKey])
        let fileSize = Int64(resourceValues.fileSize ?? 0)
        let uti = resourceValues.typeIdentifier ?? UTType.data.identifier
        let fileData = try Data(contentsOf: url)
        let initialMetadata = await metadataExtractor.extractInitialMetadata(from: url, data: fileData, uti: uti)

        // Create document record
        let document = Document(
            title: initialMetadata.title?.nilIfBlank ?? url.deletingPathExtension().lastPathComponent,
            originalFilename: url.lastPathComponent,
            fileType: uti,
            fileSize: fileSize,
            fileData: fileData
        )
        document.storagePath = url.path
        document.processingError = nil
        document.correspondent = initialMetadata.correspondent?.nilIfBlank
        document.documentDate = initialMetadata.documentDate
        modelContext.insert(document)

        do {
            // Step 1: Extract text
            document.processingStatus = .extractingText
            let extractedText = try await extractText(from: url, data: fileData, uti: uti)
            document.extractedText = extractedText
            let refinedMetadata = metadataExtractor.refineMetadata(initialMetadata, withText: extractedText)
            applyMetadata(refinedMetadata, to: document)

            // Step 2: Analyze & tag
            if !extractedText.isEmpty {
                document.processingStatus = .tagging
                await classifyAndTag(document: document, text: extractedText, metadata: refinedMetadata)
            } else {
                let fallback = OfflineDocumentClassifier.classify(
                    text: "",
                    filename: document.originalFilename,
                    metadata: refinedMetadata
                )
                applyClassification(fallback, to: document)
            }

            // Finalize
            document.processingStatus = .complete
            document.rebuildSearchableText()
            try modelContext.save()

            // Index in vector store for RAG (non-fatal if it fails — no model installed yet)
            if !extractedText.isEmpty, let ragService {
                try? await ragService.indexDocument(id: document.id, text: extractedText)
            }
        } catch {
            document.processingStatus = .failed
            document.processingError = error.localizedDescription
            document.modifiedAt = .now
            document.rebuildSearchableText()
            try? modelContext.save()
            throw error
        }
    }

    // MARK: - Text Extraction

    private func extractText(from url: URL, data: Data, uti: String) async throws -> String {
        let utType = UTType(uti)

        // PDF — with scanned document detection
        if utType?.conforms(to: .pdf) == true {
            return try await extractTextFromPDF(data: data)
        }

        // Plain text / source code
        if utType?.conforms(to: .plainText) == true || utType?.conforms(to: .sourceCode) == true {
            return String(data: data, encoding: .utf8) ?? ""
        }

        // Rich text (RTF / RTFD)
        if utType?.conforms(to: .rtf) == true || utType?.conforms(to: .rtfd) == true {
            if let attr = NSAttributedString(rtf: data, documentAttributes: nil) {
                return attr.string
            }
        }

        // Word documents (.docx) — use AppKit's built-in support
        if url.pathExtension.lowercased() == "docx" || url.pathExtension.lowercased() == "doc" {
            return try extractTextFromWord(url: url, data: data)
        }

        // Images → MiniCPM-V smart OCR when installed; Apple Vision OCR fallback otherwise.
        if utType?.conforms(to: .image) == true {
            return try await llmService.generateFromImage(
                imageData: data,
                prompt: TaggingPrompts.ocrPrompt,
                maxTokens: 2048
            )
        }

        return ""
    }

    // MARK: - PDF Extraction with Scanned Document Detection

    private func extractTextFromPDF(data: Data) async throws -> String {
        guard let pdf = PDFDocument(data: data) else { return "" }

        // First pass: try native text extraction
        var text = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let pageText = page.string {
                text += pageText + "\n"
            }
        }

        // Detect scanned PDF: if average characters per page is very low
        let avgCharsPerPage = pdf.pageCount > 0 ? text.trimmingCharacters(in: .whitespacesAndNewlines).count / pdf.pageCount : 0

        if avgCharsPerPage < scannedPDFThreshold && pdf.pageCount > 0 {
            // Scanned PDF detected — run OCR via Apple Vision framework
            return try await ocrService.recognizeTextInPDF(data: data)
        }

        return text
    }

    // MARK: - Word Document Extraction

    /// Extract text from .doc/.docx using macOS AppKit's built-in support.
    private func extractTextFromWord(url: URL, data: Data) throws -> String {
        // Write to temp file to use NSAttributedString's file-based init
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try data.write(to: tempURL)

        // NSAttributedString on macOS can read .docx natively via AppKit
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        let attributed = try NSAttributedString(
            url: tempURL,
            options: options,
            documentAttributes: nil
        )

        return attributed.string
    }

    // MARK: - LLM Classification

    private func classifyAndTag(document: Document, text: String, metadata: ExtractedDocumentMetadata) async {
        // Gather existing tags for context
        let fetchDescriptor = FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.name)])
        let existingTags = (try? modelContext.fetch(fetchDescriptor))?.map(\.name) ?? []

        let prompt = TaggingPrompts.classifyDocument(text: text, existingTags: existingTags)
        do {
            let response = try await llmService.generate(
                role: .tagger,
                prompt: prompt,
                maxTokens: 512,
                temperature: 0.1
            )
            let fallback = OfflineDocumentClassifier.classify(
                text: text,
                filename: document.originalFilename,
                metadata: metadata
            )
            let classification = ensureUsefulTags(
                parseClassification(response) ?? fallback,
                fallback: fallback
            )
            applyClassification(classification, to: document)
        } catch {
            let fallback = OfflineDocumentClassifier.classify(
                text: text,
                filename: document.originalFilename,
                metadata: metadata
            )
            applyClassification(fallback, to: document)
        }
    }

    private func parseClassification(_ response: String) -> DocumentClassification? {
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        if let firstBrace = jsonString.firstIndex(of: "{"),
           let lastBrace = jsonString.lastIndex(of: "}") {
            jsonString = String(jsonString[firstBrace...lastBrace])
        }

        guard let jsonData = jsonString.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(DocumentClassification.self, from: jsonData)
    }

    private func ensureUsefulTags(
        _ classification: DocumentClassification,
        fallback: DocumentClassification
    ) -> DocumentClassification {
        var repaired = classification
        var tags = Set(repaired.tags.map(normalizeTagName).filter { !$0.isEmpty })

        if tags.count < 2 {
            tags.formUnion(fallback.tags.map(normalizeTagName).filter { !$0.isEmpty })
        }

        if tags.isEmpty {
            tags.insert("document")
            tags.insert("to-review")
        } else if tags.count == 1 {
            tags.insert("to-review")
        }

        repaired.tags = Array(tags).sorted()
        return repaired
    }

    private func applyMetadata(_ metadata: ExtractedDocumentMetadata, to document: Document) {
        if document.correspondent?.nilIfBlank == nil {
            document.correspondent = metadata.correspondent?.nilIfBlank
        }
        if document.documentDate == nil {
            document.documentDate = metadata.documentDate
        }
    }

    private func applyClassification(_ classification: DocumentClassification, to document: Document) {
        if let title = classification.title?.nilIfBlank {
            document.title = title
        }
        if let summary = classification.summary?.nilIfBlank {
            document.summary = summary
        }
        if let correspondent = classification.correspondent?.nilIfBlank {
            document.correspondent = correspondent
        }
        if let dateString = classification.date?.nilIfBlank,
           let date = DocumentMetadataExtractor.parseDate(dateString) {
            document.documentDate = date
        }

        // Resolve taxonomy fields against the canonical 500-type list. The LLM
        // sometimes invents a slug or returns the display name — sanitize both.
        if let rawType = classification.documentType?.nilIfBlank {
            let typeSlug = canonicalize(rawType)
            if let type = DocumentTaxonomy.type(forSlug: typeSlug) {
                document.documentTypeSlug = type.slug
                // Snap the category to the type's actual parent (LLM may
                // disagree with the canonical mapping).
                document.categorySlug = DocumentTaxonomy.category(containingTypeSlug: type.slug)?.slug
            }
        }
        // If type was missing/invalid but category resolves on its own, keep it.
        if document.categorySlug == nil, let rawCategory = classification.category?.nilIfBlank {
            let catSlug = canonicalize(rawCategory)
            if let cat = DocumentTaxonomy.category(forSlug: catSlug) {
                document.categorySlug = cat.slug
            }
        }

        for tagName in classification.tags {
            attachTag(named: tagName, to: document)
        }

        // Also attach the document_type as a tag so it shows up in search/filtering.
        if let typeSlug = document.documentTypeSlug {
            attachTag(named: typeSlug, to: document)
        }
    }

    /// Loose normalizer for slugs returned by the LLM: lowercases, replaces
    /// whitespace/underscores with hyphens, strips anything outside [a-z0-9-].
    private func canonicalize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let mapped = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.lowercaseLetters.contains(scalar) ||
                CharacterSet.decimalDigits.contains(scalar) ||
                scalar == "-" {
                return Character(scalar)
            }
            return "-"
        }
        return String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }

    private func attachTag(named rawName: String, to document: Document) {
        let normalized = normalizeTagName(rawName)
        guard !normalized.isEmpty else { return }

        // Reuse existing tag or create new
        let predicate = #Predicate<Tag> { $0.name == normalized }
        let descriptor = FetchDescriptor<Tag>(predicate: predicate)
        let existing = try? modelContext.fetch(descriptor).first

        let tag = existing ?? Tag(
            name: normalized,
            colorHex: Tag.defaultColors.randomElement() ?? "2A639D"
        )
        if existing == nil {
            modelContext.insert(tag)
        }
        if document.tags == nil { document.tags = [] }
        if !(document.tags?.contains(where: { $0.name == normalized }) ?? false) {
            document.tags?.append(tag)
        }
    }

    private func normalizeTagName(_ rawName: String) -> String {
        rawName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: "-")
    }

    private func cleanupTemporaryImportFileIfNeeded(_ url: URL) {
        let tempDirectory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let standardizedURL = url.standardizedFileURL
        guard standardizedURL.deletingLastPathComponent().path == tempDirectory,
              standardizedURL.lastPathComponent.hasPrefix("athenaeum-drop-") else {
            return
        }
        try? FileManager.default.removeItem(at: standardizedURL)
    }

    private func documentAlreadyExists(for url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        let fetch = FetchDescriptor<Document>()
        let documents = (try? modelContext.fetch(fetch)) ?? []

        return documents.contains { document in
            if document.storagePath == path { return true }
            guard let size, document.fileSize == size else { return false }
            return document.originalFilename == url.lastPathComponent
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
