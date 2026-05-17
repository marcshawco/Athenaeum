import Foundation
import AppKit
import PDFKit
import SwiftData
import UniformTypeIdentifiers

enum LLMRole: String, CaseIterable, Sendable {
    case tagger
    case chat
    case vision
}

struct LLMModelDescriptor: Sendable {
    let role: LLMRole
    let displayName: String
    let filename: String
    let parameterSize: String
    let quantization: String
}

enum ChatRole: String, Sendable, Codable {
    case system, user, assistant
}

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date

    init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = .now
    }
}

protocol LLMServiceProtocol: Sendable {
    func isModelAvailable(_ descriptor: LLMModelDescriptor) -> Bool
    func loadModel(_ descriptor: LLMModelDescriptor) async throws
    func unloadModel(_ role: LLMRole) async
    func generate(role: LLMRole, prompt: String, maxTokens: Int, temperature: Float) async throws -> String
    func generateFromImage(imageData: Data, prompt: String, maxTokens: Int) async throws -> String
    func generateStream(role: LLMRole, messages: [ChatMessage], maxTokens: Int, temperature: Float) -> AsyncThrowingStream<String, Error>
    func embed(role: LLMRole, text: String) async throws -> [Float]
}

enum LlamaError: LocalizedError {
    case modelNotFound(String)
}

enum TaggingPrompts {
    static func classifyDocument(text: String, existingTags: [String]) -> String {
        let availableTags = Array(Set(Tag.builtInPool + existingTags)).sorted()
        return """
        Return valid JSON with title, tags, correspondent, date, and summary.
        Prefer these tags: \(availableTags.joined(separator: ", "))
        Document text:
        \(String(text.prefix(4000)))
        """
    }

    static var ocrPrompt: String {
        "Extract all visible text from this image. Return only the extracted text."
    }
}

private enum SmokeError: LocalizedError {
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .failure(let message): message
        }
    }
}

private final class SmokeLLM: LLMServiceProtocol, @unchecked Sendable {
    enum TaggingMode {
        case throwForFallback
        case validJSON
    }

    private let taggingMode: TaggingMode
    private let lock = NSLock()
    private(set) var generateCalls = 0
    private(set) var streamMessages: [ChatMessage] = []
    private let ocr = VisionOCRService()

    init(taggingMode: TaggingMode) {
        self.taggingMode = taggingMode
    }

    func isModelAvailable(_ descriptor: LLMModelDescriptor) -> Bool { false }
    func loadModel(_ descriptor: LLMModelDescriptor) async throws {}
    func unloadModel(_ role: LLMRole) async {}

    func generate(role: LLMRole, prompt: String, maxTokens: Int, temperature: Float) async throws -> String {
        lock.withLock { generateCalls += 1 }
        switch taggingMode {
        case .throwForFallback:
            throw LlamaError.modelNotFound("Smoke test simulates missing local model")
        case .validJSON:
            return """
            {"title":"AI Tagged Lease Agreement","tags":["lease","contract","legal"],"correspondent":"Northstar Studio","date":"2026-03-14","summary":"Lease agreement tagged by the local LLM path."}
            """
        }
    }

    func generateFromImage(imageData: Data, prompt: String, maxTokens: Int) async throws -> String {
        try await ocr.recognizeText(in: imageData)
    }

    func generateStream(role: LLMRole, messages: [ChatMessage], maxTokens: Int, temperature: Float) -> AsyncThrowingStream<String, Error> {
        lock.withLock { streamMessages = messages }
        let hasHistory = messages.filter { $0.role == .user }.count > 1
        let response = hasHistory
            ? "Following up from the previous turn: the amount due is $1,240. [Source 1]"
            : "Northstar Studio appears in the retrieved document context. [Source 1]"
        return AsyncThrowingStream { continuation in
            for token in response.split(separator: " ", omittingEmptySubsequences: false) {
                continuation.yield(String(token) + " ")
            }
            continuation.finish()
        }
    }

    func embed(role: LLMRole, text: String) async throws -> [Float] {
        throw LlamaError.modelNotFound("Smoke test uses RAG pseudo-embeddings")
    }
}

@main
struct EndToEndSmokeTest {
    @MainActor
    static func main() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("athenaeum-e2e-smoke-\(UUID().uuidString)", isDirectory: true)
        let vault = root.appendingPathComponent("Athenaeum Library", isDirectory: true)
        let fixtures = root.appendingPathComponent("Fixtures", isDirectory: true)
        try fileManager.createDirectory(at: vault, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: fixtures, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        UserDefaults.standard.removeObject(forKey: "documentVaultBookmark")
        UserDefaults.standard.set(vault.path, forKey: "documentVaultPath")

        let preparedVault = try DocumentVaultService.shared.prepareVault()
        try assert(preparedVault.standardizedFileURL == vault.standardizedFileURL, "Vault path did not persist through prepareVault")
        try assert(DocumentVaultService.shared.vaultURL.standardizedFileURL == vault.standardizedFileURL, "Vault URL did not reload from stored path")

        let txt = fixtures.appendingPathComponent("northstar-invoice.txt")
        try """
        Invoice
        From: Northstar Studio
        Date: 2026-03-14
        Amount due: $1,240
        Payment terms: Net 15
        """.write(to: txt, atomically: true, encoding: .utf8)

        let pdf = fixtures.appendingPathComponent("lease-agreement.pdf")
        try writePDF(
            text: "Lease Agreement\nTenant: Northstar Studio\nDate: 2026-03-14\nRent amount due: $1,240\nSignature required.",
            to: pdf
        )

        let docx = fixtures.appendingPathComponent("benefits-summary.docx")
        try writeDOCX(
            text: "Benefits Summary\nPatient: Avery Shaw\nInsurance premium and deductible information.\nDate: 2026-02-10",
            to: docx
        )

        let image = fixtures.appendingPathComponent("scanned-receipt.png")
        try writeImageScan(
            text: "Receipt\nNorthstar Studio\nTotal paid $84.19\nDate 2026-01-22",
            to: image
        )

        let container = try ModelContainer(
            for: Document.self,
            Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let fallbackLLM = SmokeLLM(taggingMode: .throwForFallback)
        let rag = RAGService(
            llmService: fallbackLLM,
            vectorStore: VectorStore(storageURL: root.appendingPathComponent("vector_store.json"))
        )
        let processor = DocumentProcessor(llmService: fallbackLLM, ragService: rag, modelContext: context)

        let initialImportCount = await processor.importFiles([pdf, docx, txt, image])
        try assert(initialImportCount == 4, "Expected 4 queued imports, got \(initialImportCount)")
        var documents = try context.fetch(FetchDescriptor<Document>())
        try assert(documents.count == 4, "Expected 4 imported documents, got \(documents.count)")
        try assert(documents.allSatisfy { $0.processingStatus == .complete }, "Not every imported document completed processing")
        try assert(documents.allSatisfy { ($0.storagePath ?? "").hasPrefix(vault.path) }, "Imported files were not copied into the vault")
        try assert(documents.allSatisfy { ($0.tags ?? []).count >= 2 }, "Fallback tagging did not assign at least two tags to every document")
        try assert(fallbackLLM.generateCalls > 0, "Fallback tagging path did not exercise the missing-model LLM call")

        let duplicateImportCount = await processor.importFiles([pdf])
        try assert(duplicateImportCount == 0, "Duplicate import should queue 0 documents, got \(duplicateImportCount)")

        let tempDropURL = fileManager.temporaryDirectory
            .appendingPathComponent("athenaeum-drop-smoke-\(UUID().uuidString)")
            .appendingPathExtension("txt")
        try "Temporary drag/drop note. Amount due $45. Date: 2026-04-02.".write(to: tempDropURL, atomically: true, encoding: .utf8)
        let tempDropImportCount = await processor.importFiles([tempDropURL])
        try assert(tempDropImportCount == 1, "Temp drop import should queue 1 document, got \(tempDropImportCount)")
        try assert(!fileManager.fileExists(atPath: tempDropURL.path), "Temporary drag/drop file was not cleaned up")

        let finderDrop = vault.appendingPathComponent("finder-added-contract.txt")
        try "Contract added directly in Finder. Amount due $600. Date: 2026-04-01.".write(to: finderDrop, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -5)], ofItemAtPath: finderDrop.path)
        let scannedCount = await processor.scanVaultForNewDocuments()
        try assert(scannedCount == 1, "Vault scan should import 1 Finder-added document, got \(scannedCount)")

        documents = try context.fetch(FetchDescriptor<Document>())
        try assert(documents.count == 6, "Expected 6 documents after vault scan, got \(documents.count)")

        let aiContainer = try ModelContainer(
            for: Document.self,
            Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let aiContext = ModelContext(aiContainer)
        let aiLLM = SmokeLLM(taggingMode: .validJSON)
        let aiProcessor = DocumentProcessor(llmService: aiLLM, modelContext: aiContext)
        await aiProcessor.importFiles([pdf])
        let aiDocument = try unwrap(try aiContext.fetch(FetchDescriptor<Document>()).first, "AI-tagged document was not imported")
        let aiTags = Set((aiDocument.tags ?? []).map(\.name))
        try assert(aiTags.isSuperset(of: ["lease", "contract"]), "AI JSON tagging did not apply expected tags: \(aiTags)")

        let contexts = documents.compactMap { document -> RAGDocumentContext? in
            guard let text = document.extractedText, !text.isEmpty else { return nil }
            return RAGDocumentContext(
                id: document.id,
                title: document.title,
                text: text,
                documentDate: document.documentDate,
                importedAt: document.importedAt
            )
        }
        try assert(!contexts.isEmpty, "No document text was available for RAG contexts")

        for document in documents {
            if let text = document.extractedText, !text.isEmpty {
                try await rag.indexDocument(id: document.id, text: text)
            }
        }

        let first = try await rag.queryStream(
            "Who is named in the invoice?",
            history: [],
            maxContext: 5,
            fallbackDocuments: contexts
        )
        let firstAnswer = try await collect(first.stream)
        try assert(first.sources.isEmpty == false, "RAG query returned no sources")
        try assert(firstAnswer.contains("[Source 1]"), "RAG answer did not cite a source: \(firstAnswer)")

        let followupHistory = [
            ChatMessage(role: .user, content: "Who is named in the invoice?"),
            ChatMessage(role: .assistant, content: firstAnswer)
        ]
        let second = try await rag.queryStream(
            "What amount is due?",
            history: followupHistory,
            maxContext: 5,
            fallbackDocuments: contexts
        )
        let secondAnswer = try await collect(second.stream)
        try assert(second.sources.isEmpty == false, "Follow-up RAG query returned no sources")
        try assert(secondAnswer.contains("$1,240") && secondAnswer.contains("[Source 1]"), "Follow-up RAG answer did not preserve context and citation: \(secondAnswer)")
        try assert(fallbackLLM.streamMessages.contains { $0.role == .assistant && $0.content == firstAnswer }, "Chat history was not passed into follow-up RAG generation")

        let imageDocument = try unwrap(documents.first { $0.originalFilename == "scanned-receipt.png" }, "Image scan document missing")
        try assert((imageDocument.extractedText ?? "").localizedCaseInsensitiveContains("Northstar"), "Image OCR did not recover expected text: \(imageDocument.extractedText ?? "")")

        print("End-to-end smoke test passed")
        print("Imported PDF, DOCX, TXT, and image scan into a clean library")
        print("Vault path persisted and Finder-added vault scan imported 1 new document")
        print("Fallback tagging, AI JSON tagging path, OCR fallback, RAG citations, and follow-up history all passed")
    }

    private static func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var output = ""
        for try await token in stream {
            output += token
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func writePDF(text: String, to url: URL) throws {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw SmokeError.failure("Could not create PDF context")
        }

        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 18),
                .foregroundColor: NSColor.black
            ]
        )
        attributed.draw(in: CGRect(x: 72, y: 220, width: 468, height: 400))
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()

        try (data as Data).write(to: url)
    }

    private static func writeDOCX(text: String, to url: URL) throws {
        let source = url.deletingPathExtension().appendingPathExtension("txt")
        try text.write(to: source, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "docx", "-output", url.path, source.path]
        try process.run()
        process.waitUntilExit()
        try assert(process.terminationStatus == 0, "textutil failed to create DOCX")
    }

    private static func writeImageScan(text: String, to url: URL) throws {
        let image = NSImage(size: NSSize(width: 1200, height: 520))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 520).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 54, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        (text as NSString).draw(in: NSRect(x: 70, y: 80, width: 1060, height: 360), withAttributes: attributes)
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SmokeError.failure("Could not render image scan")
        }
        try png.write(to: url)
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw SmokeError.failure(message) }
        return value
    }

    private static func assert(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw SmokeError.failure(message) }
    }
}
