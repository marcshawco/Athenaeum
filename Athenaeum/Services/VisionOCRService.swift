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

    /// Cap on pages we OCR per PDF. Beyond this we bail out so a 5,000-page
    /// PDF doesn't pin the app rendering page bitmaps for hours.
    private static let maxPDFPagesForOCR: Int = 200

    /// Cap on per-page bitmap area (pixels) before we scale down. A 5000x5000-pt
    /// page at 2× = 100 megapixels × 4 bytes/px = 400 MB per page. We clamp the
    /// effective scale so the per-page allocation stays under ~64 MB.
    private static let maxPagePixelCount: Int = 16_000_000  // 16 megapixels ≈ 64 MB RGBA

    /// OCR all pages of a PDF, returning structured text with page markers.
    /// Skips pages whose backing bitmap allocation would exceed `maxPagePixelCount`
    /// after scale clamping. Stops after `maxPDFPagesForOCR` pages.
    func recognizeTextInPDF(data: Data) async throws -> String {
        guard let provider = CGDataProvider(data: data as CFData),
              let pdf = CGPDFDocument(provider) else {
            throw OCRError.invalidPDFData
        }

        var fullText = ""
        let totalPages = pdf.numberOfPages
        let pageCount = min(totalPages, Self.maxPDFPagesForOCR)
        if pageCount == 0 { return "" }

        for pageIndex in 1...pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }

            let pageRect = page.getBoxRect(.mediaBox)
            guard pageRect.width > 0, pageRect.height > 0 else { continue }

            // Render at 2× for OCR quality, but clamp the effective scale
            // so absurdly large pages don't request gigabytes of bitmap.
            let preferredScale: CGFloat = 2.0
            let preferredPixels = Double(pageRect.width) * Double(pageRect.height) * Double(preferredScale * preferredScale)
            let scale: CGFloat
            if preferredPixels > Double(Self.maxPagePixelCount) {
                let scaleSquared = Double(Self.maxPagePixelCount) / (Double(pageRect.width) * Double(pageRect.height))
                guard scaleSquared > 0 else { continue }
                scale = CGFloat(scaleSquared.squareRoot())
            } else {
                scale = preferredScale
            }
            let width = Int(pageRect.width * scale)
            let height = Int(pageRect.height * scale)
            guard width > 0, height > 0,
                  width * height <= Self.maxPagePixelCount else { continue }

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

        if totalPages > pageCount {
            fullText += "\n[OCR stopped at page \(pageCount) of \(totalPages) — re-import a smaller PDF to OCR the remainder]\n"
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
