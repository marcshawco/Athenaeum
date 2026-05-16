import Foundation
import Vision
import AppKit

// MARK: - Native macOS OCR via Apple Vision Framework
//
// Uses VNRecognizeTextRequest for on-device text recognition.
// Runs entirely locally on Apple Silicon — no model download required.
// Supports both accurate (slow) and fast recognition modes.

actor VisionOCRService {

    enum RecognitionLevel {
        case fast      // Low latency, good for previews
        case accurate  // Higher quality, better for archival OCR
    }

    /// Recognize text in image data (PNG, JPEG, TIFF, etc.)
    func recognizeText(
        in imageData: Data,
        level: RecognitionLevel = .accurate,
        languages: [String] = ["en"]
    ) async throws -> String {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImageData
        }

        return try await recognizeText(in: cgImage, level: level, languages: languages)
    }

    /// Recognize text in a CGImage
    func recognizeText(
        in cgImage: CGImage,
        level: RecognitionLevel = .accurate,
        languages: [String] = ["en"]
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                // Sort observations by position: top-to-bottom, left-to-right
                let sorted = observations.sorted { a, b in
                    // Vision coordinates: origin at bottom-left, y increases upward
                    // For reading order: higher y = earlier in page (top of page)
                    let aY = a.boundingBox.origin.y + a.boundingBox.height
                    let bY = b.boundingBox.origin.y + b.boundingBox.height

                    // Group into lines: observations within 2% vertical distance are same line
                    if abs(aY - bY) < 0.02 {
                        return a.boundingBox.origin.x < b.boundingBox.origin.x
                    }
                    return aY > bY // Higher y = earlier (top of page)
                }

                let text = sorted.compactMap { observation -> String? in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: text)
            }

            request.recognitionLevel = level == .accurate ? .accurate : .fast
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    /// OCR all pages of a PDF, returning structured text with page markers.
    func recognizeTextInPDF(data: Data) async throws -> String {
        guard let provider = CGDataProvider(data: data as CFData),
              let pdf = CGPDFDocument(provider) else {
            throw OCRError.invalidPDFData
        }

        var fullText = ""
        let pageCount = pdf.numberOfPages

        for pageIndex in 1...pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }

            let pageRect = page.getBoxRect(.mediaBox)

            // Render at 2x for better OCR accuracy
            let scale: CGFloat = 2.0
            let width = Int(pageRect.width * scale)
            let height = Int(pageRect.height * scale)

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }

            // White background
            context.setFillColor(CGColor.white)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // Scale and draw PDF page
            context.scaleBy(x: scale, y: scale)
            context.drawPDFPage(page)

            guard let cgImage = context.makeImage() else { continue }

            let pageText = try await recognizeText(in: cgImage)

            if !pageText.isEmpty {
                if pageCount > 1 {
                    fullText += "--- Page \(pageIndex) ---\n"
                }
                fullText += pageText + "\n\n"
            }
        }

        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errors

enum OCRError: LocalizedError {
    case invalidImageData
    case invalidPDFData
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImageData:          "Could not create image from provided data"
        case .invalidPDFData:            "Could not create PDF from provided data"
        case .recognitionFailed(let msg): "Text recognition failed: \(msg)"
        }
    }
}
