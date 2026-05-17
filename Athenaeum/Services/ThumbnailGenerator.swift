import Foundation
import AppKit
import PDFKit
import QuickLookThumbnailing

// MARK: - Thumbnail Generator
// Generates preview thumbnails for documents using QuickLook and PDFKit.

actor ThumbnailGenerator {
    private var cache: [UUID: NSImage] = [:]
    private let thumbnailSize = CGSize(width: 200, height: 260)

    // MARK: - Public API

    func thumbnail(for document: Document) async -> NSImage? {
        // Check cache
        if let cached = cache[document.id] {
            return cached
        }

        // Generate from the Finder-visible vault original first; SwiftData's
        // external blob is only a backup for older or repaired records.
        let data = fileData(for: document)
        let image: NSImage?
        if document.isPDF {
            image = await generatePDFThumbnail(data: data)
        } else if document.isImage {
            image = generateImageThumbnail(data: data)
        } else {
            image = await generateQuickLookThumbnail(
                data: data,
                filename: document.originalFilename
            )
        }

        if let image {
            cache[document.id] = image
        }
        return image
    }

    private func fileData(for document: Document) -> Data? {
        if let url = document.storedFileURL,
           FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url) {
            return data
        }
        return document.fileData
    }

    func clearCache(for documentID: UUID) {
        cache.removeValue(forKey: documentID)
    }

    func clearAllCache() {
        cache.removeAll()
    }

    // MARK: - PDF Thumbnail

    private func generatePDFThumbnail(data: Data?) async -> NSImage? {
        guard let data, let pdf = PDFDocument(data: data),
              let page = pdf.page(at: 0) else { return nil }

        let pageRect = page.bounds(for: .mediaBox)
        let scale = min(
            thumbnailSize.width / pageRect.width,
            thumbnailSize.height / pageRect.height
        )
        let scaledSize = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        let image = NSImage(size: scaledSize)
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            // White background
            context.setFillColor(.white)
            context.fill(CGRect(origin: .zero, size: scaledSize))

            // Draw PDF page
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
        }

        image.unlockFocus()
        return image
    }

    // MARK: - Image Thumbnail

    private func generateImageThumbnail(data: Data?) -> NSImage? {
        guard let data, let original = NSImage(data: data) else { return nil }

        let originalSize = original.size
        let scale = min(
            thumbnailSize.width / originalSize.width,
            thumbnailSize.height / originalSize.height,
            1.0 // Don't upscale
        )
        let scaledSize = CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        let thumbnail = NSImage(size: scaledSize)
        thumbnail.lockFocus()
        original.draw(
            in: CGRect(origin: .zero, size: scaledSize),
            from: CGRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()
        return thumbnail
    }

    // MARK: - QuickLook Thumbnail

    private func generateQuickLookThumbnail(data: Data?, filename: String) async -> NSImage? {
        guard let data else { return nil }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension((filename as NSString).pathExtension)

        do {
            try data.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let request = QLThumbnailGenerator.Request(
                fileAt: tempURL,
                size: thumbnailSize,
                scale: 2.0,
                representationTypes: .thumbnail
            )

            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return representation.nsImage
        } catch {
            return nil
        }
    }
}

// MARK: - Thumbnail View

import SwiftUI

struct DocumentThumbnailView: View {
    let document: Document
    var size: CGSize = CGSize(width: 100, height: 130)
    var normalizesDocumentSize = false

    @State private var thumbnail: NSImage?
    @State private var isLoading = true

    private static let generator = ThumbnailGenerator()

    var body: some View {
        Group {
            if let thumbnail {
                thumbnailImage(thumbnail)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
            } else {
                fallbackIcon
            }
        }
        .frame(width: size.width, height: size.height)
        .background(
            LinearGradient(
                colors: [
                    Japandi.Colors.surfaceRaisedFB,
                    Japandi.Colors.washFallback.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous)
                .strokeBorder(Japandi.Colors.borderFallback.opacity(0.65), lineWidth: 0.75)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.42))
                .frame(height: 1)
        }
        .task {
            thumbnail = await Self.generator.thumbnail(for: document)
            isLoading = false
        }
    }

    @ViewBuilder
    private func thumbnailImage(_ thumbnail: NSImage) -> some View {
        if normalizesDocumentSize {
            normalizedDocumentPreview(fillsPaper: true) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        } else {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    private var fallbackIcon: some View {
        Group {
            if normalizesDocumentSize {
                normalizedDocumentPreview(fillsPaper: false) {
                    Image(systemName: iconForDocument)
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(Japandi.Colors.accentMutedFallback)
                }
            } else {
                Image(systemName: iconForDocument)
                    .font(.system(size: 28, weight: .ultraLight))
                    .foregroundStyle(Japandi.Colors.accentMutedFallback)
            }
        }
    }

    private func normalizedDocumentPreview<Content: View>(
        fillsPaper: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let paperWidth = min(size.width * 0.46, 96)
        let paperHeight = min(size.height * 0.76, 112)
        let inset: CGFloat = 7
        let innerSize = CGSize(
            width: max(1, paperWidth - inset * 2),
            height: max(1, paperHeight - inset * 2)
        )

        return ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.94))
                .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 3)

            content()
                .frame(width: fillsPaper ? innerSize.width : paperWidth,
                       height: fillsPaper ? innerSize.height : paperHeight)
                .clipped()
        }
        .frame(width: paperWidth, height: paperHeight)
        .frame(width: size.width, height: size.height)
    }

    private var iconForDocument: String {
        if document.isPDF { return "doc.richtext" }
        if document.isImage { return "photo" }
        switch document.fileExtension {
        case "doc", "docx": return "doc.text"
        case "txt":         return "doc.plaintext"
        case "rtf", "rtfd": return "doc.richtext"
        default:            return "doc"
        }
    }
}
