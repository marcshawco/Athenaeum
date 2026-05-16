import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AppKit

struct DocumentPreviewWindow: View {
    let document: Document
    var showsCloseButton = true
    @Environment(\.dismiss) private var dismiss
    @State private var tempURL: URL?

    private var utType: UTType? {
        UTType(document.fileType) ?? UTType(filenameExtension: document.fileExtension)
    }

    private var isTextLike: Bool {
        if utType?.conforms(to: .text) == true { return true }
        return ["txt", "md", "csv", "json", "xml", "log"].contains(document.fileExtension)
    }

    private var isImageLike: Bool {
        if utType?.conforms(to: .image) == true { return true }
        return document.isImage
    }

    var body: some View {
        VStack(spacing: 0) {
            previewToolbar
            Divider().foregroundStyle(Japandi.Colors.borderFallback)
            previewBody
        }
        .background(Japandi.Colors.bgFallback)
        .onDisappear {
            if let tempURL {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
    }

    private var previewToolbar: some View {
        HStack(spacing: Japandi.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(Japandi.Typography.headline)
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    .lineLimit(1)

                Text("\(document.originalFilename) · \(document.fileSizeFormatted)")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                openInDefaultApp()
            } label: {
                Label("Open Externally", systemImage: "arrow.up.forward.app")
                    .font(Japandi.Typography.caption)
            }
            .buttonStyle(.borderless)
            .disabled(availableFileData == nil && document.storedFileURL == nil)

            if showsCloseButton {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Japandi.Colors.textSecondaryFB)
                        .frame(width: 28, height: 28)
                        .background(Japandi.Colors.surfaceRaisedFB)
                        .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Japandi.Spacing.md)
        .padding(.vertical, Japandi.Spacing.sm)
        .background(Japandi.Colors.surfaceRaisedFB.opacity(0.72))
    }

    @ViewBuilder
    private var previewBody: some View {
        if availableFileData == nil && document.storedFileURL == nil {
            unavailableView(
                title: "Original file is unavailable",
                message: "Athenaeum has the document record, but the stored file data is missing."
            )
        } else if document.isPDF, let data = availableFileData, let pdf = PDFDocument(data: data) {
            PDFKitPreview(document: pdf)
        } else if isImageLike, let data = availableFileData, let image = NSImage(data: data) {
            imagePreview(image)
        } else if isTextLike, let text = textContent {
            textPreview(text)
        } else if let extracted = document.extractedText, !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            extractedTextPreview(extracted)
        } else {
            unsupportedPreview
        }
    }

    private func imagePreview(_ image: NSImage) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(Japandi.Spacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Japandi.Colors.inkFallback.opacity(0.04))
    }

    private func textPreview(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(Japandi.Typography.mono)
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Japandi.Spacing.lg)
        }
        .background(Japandi.Colors.surfaceRaisedFB)
    }

    private func extractedTextPreview(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Extracted text preview")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                Spacer()
            }
            .padding(.horizontal, Japandi.Spacing.lg)
            .padding(.vertical, Japandi.Spacing.xs)
            .background(Japandi.Colors.surfaceFallback)

            textPreview(text)
        }
    }

    private var unsupportedPreview: some View {
        unavailableView(
            title: "Preview is not available for this file type",
            message: "The document is stored in Athenaeum. Open it externally to view the original file."
        )
    }

    private func unavailableView(title: String, message: String) -> some View {
        VStack(spacing: Japandi.Spacing.md) {
            DocumentThumbnailView(document: document, size: CGSize(width: 160, height: 208))

            VStack(spacing: Japandi.Spacing.xs) {
                Text(title)
                    .font(Japandi.Typography.title)
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)

                Text(message)
                    .font(Japandi.Typography.body)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Button {
                openInDefaultApp()
            } label: {
                Label("Open Externally", systemImage: "arrow.up.forward.app")
                    .font(Japandi.Typography.body)
            }
            .buttonStyle(.borderedProminent)
            .tint(Japandi.Colors.accentFallback)
            .disabled(availableFileData == nil && document.storedFileURL == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Japandi.Spacing.xl)
    }

    private var textContent: String? {
        guard let data = availableFileData else { return document.extractedText }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let utf16 = String(data: data, encoding: .utf16) { return utf16 }
        return document.extractedText
    }

    private var availableFileData: Data? {
        if let url = document.storedFileURL,
           FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url) {
            return data
        }
        return document.fileData
    }

    private func openInDefaultApp() {
        guard let url = materializeTempFile() else { return }
        NSWorkspace.shared.open(url)
    }

    private func materializeTempFile() -> URL? {
        if let tempURL, FileManager.default.fileExists(atPath: tempURL.path) {
            return tempURL
        }
        if let storedURL = document.storedFileURL,
           FileManager.default.fileExists(atPath: storedURL.path) {
            return storedURL
        }

        guard let data = availableFileData else { return nil }
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("athenaeum-preview-\(document.id.uuidString)")
        let url = document.fileExtension.isEmpty ? base : base.appendingPathExtension(document.fileExtension)

        do {
            try data.write(to: url, options: .atomic)
            tempURL = url
            return url
        } catch {
            return nil
        }
    }
}

private struct PDFKitPreview: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor(Japandi.Colors.bgFallback)
        view.document = document
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
        nsView.autoScales = true
    }
}
