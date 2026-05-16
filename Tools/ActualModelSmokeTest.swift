import Foundation
import AppKit

private enum ActualModelSmokeError: LocalizedError {
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .failure(let message): message
        }
    }
}

@main
struct ActualModelSmokeTest {
    static func main() async throws {
        let manager = ModelManager()
        manager.scanForModels()

        let availableRoles = Set(manager.availableModels.keys)
        try assert(
            availableRoles.isSuperset(of: Set(LLMRole.allCases)),
            "Missing installed models. Found roles: \(availableRoles.map(\.rawValue).sorted())"
        )

        let service = LocalLLMService(modelManager: manager)

        let invoiceText = """
        Invoice
        From: Northstar Studio
        Date: 2026-03-14
        Amount due: $1,240
        Payment terms: Net 15
        """

        let tagJSON = try await service.generate(
            role: .tagger,
            prompt: TaggingPrompts.classifyDocument(text: invoiceText, existingTags: []),
            maxTokens: 256,
            temperature: 0.1
        )
        let classification = try parseClassification(tagJSON)
        try assert(classification.tags.count >= 2, "Qwen tagging returned fewer than two tags: \(tagJSON)")
        await service.unloadModel(.tagger)

        let vectorStore = VectorStore(
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("athenaeum-actual-model-vector-\(UUID().uuidString).json")
        )
        let rag = RAGService(llmService: service, vectorStore: vectorStore)
        let documentID = UUID()
        try await rag.indexDocument(id: documentID, text: invoiceText)
        let response = try await rag.query("What amount is due and who sent the invoice?", maxContext: 3)
        try assert(!response.sources.isEmpty, "Mistral RAG returned no retrieved sources")
        try assert(!response.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Mistral RAG returned an empty answer")
        await service.unloadModel(.chat)

        let imageData = try makeImageData(text: "Receipt\nNorthstar Studio\nTotal paid $84.19")
        let ocrText = try await service.generateFromImage(
            imageData: imageData,
            prompt: TaggingPrompts.ocrPrompt,
            maxTokens: 256
        )
        try assert(
            ocrText.localizedCaseInsensitiveContains("Northstar"),
            "MiniCPM-V/Vision OCR did not recover expected text: \(ocrText)"
        )
        await service.unloadModel(.vision)

        print("Actual model smoke test passed")
        print("Qwen tagging produced \(classification.tags.count) tags: \(classification.tags.sorted().joined(separator: ", "))")
        print("Mistral RAG returned \(response.sources.count) source(s)")
        print("MiniCPM-V OCR path recovered expected scanned text")
    }

    private static func parseClassification(_ response: String) throws -> DocumentClassification {
        var json = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = json.firstIndex(of: "{"), let last = json.lastIndex(of: "}") {
            json = String(json[first...last])
        }
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DocumentClassification.self, from: data) else {
            throw ActualModelSmokeError.failure("Could not parse Qwen classification JSON: \(response)")
        }
        return decoded
    }

    private static func makeImageData(text: String) throws -> Data {
        let image = NSImage(size: NSSize(width: 1200, height: 440))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 440).fill()
        (text as NSString).draw(
            in: NSRect(x: 70, y: 70, width: 1060, height: 300),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 56, weight: .medium),
                .foregroundColor: NSColor.black
            ]
        )
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ActualModelSmokeError.failure("Could not render image fixture")
        }
        return png
    }

    private static func assert(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw ActualModelSmokeError.failure(message) }
    }
}
