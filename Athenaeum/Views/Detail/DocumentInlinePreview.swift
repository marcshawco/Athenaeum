import SwiftUI
import PDFKit
import AppKit

// MARK: - DocumentInlinePreview
//
// Inspector-sized preview that renders the actual document — PDFKit for
// PDFs, native image rendering for images, a typeset text view for
// markdown/code/text — instead of dumping the OCR text blob as monospace.
// Sized for a fixed frame the inspector controls (~260pt tall).

struct DocumentInlinePreview: View {
    let document: Document

    var body: some View {
        Group {
            if document.isPDF, let pdf = pdfDocument {
                PDFInlineRepresentable(document: pdf)
            } else if document.isImage, let image = inlineImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.15))
            } else if let text = previewText, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.system(size: 11.5, design: textIsCode ? .monospaced : .default))
                        .foregroundStyle(Japandi.Colors.inspectorInk2)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Japandi.Spacing.sm)
                        .textSelection(.enabled)
                }
                .background(Color.white.opacity(0.04))
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc")
                .font(.system(size: 26, weight: .ultraLight))
                .foregroundStyle(Japandi.Colors.inspectorInk3)
            Text("Preview unavailable")
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.inspectorInk3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Data resolution

    /// Prefer the on-disk vault file; fall back to the externally-stored
    /// `fileData` blob if the vault file's gone.
    private var fileData: Data? {
        if let url = document.storedFileURL,
           FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url) {
            return data
        }
        return document.fileData
    }

    private var pdfDocument: PDFDocument? {
        guard let data = fileData else { return nil }
        return PDFDocument(data: data)
    }

    private var inlineImage: NSImage? {
        guard let data = fileData else { return nil }
        return NSImage(data: data)
    }

    /// Text body for non-PDF / non-image documents. We use the original file
    /// bytes if it's a text-shaped file (markdown, code, plain text), and
    /// fall back to the LLM-extracted text only as a last resort.
    private var previewText: String? {
        let ext = document.fileExtension.lowercased()
        let textyExtensions: Set<String> = [
            "txt", "md", "markdown", "log",
            "swift", "py", "js", "ts", "tsx", "jsx", "go", "rs", "rb", "java",
            "kt", "c", "cc", "cpp", "h", "hpp", "m", "mm", "sh", "zsh", "bash",
            "json", "yaml", "yml", "toml", "ini", "conf", "xml", "plist",
            "csv", "tsv", "html", "htm",
        ]
        if textyExtensions.contains(ext), let data = fileData {
            if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
            if let utf16 = String(data: data, encoding: .utf16) { return utf16 }
        }
        return document.extractedText
    }

    private var textIsCode: Bool {
        let codeExtensions: Set<String> = [
            "swift", "py", "js", "ts", "tsx", "jsx", "go", "rs", "rb", "java",
            "kt", "c", "cc", "cpp", "h", "hpp", "m", "mm", "sh", "zsh", "bash",
            "json", "yaml", "yml", "toml", "ini", "conf", "xml", "plist",
        ]
        return codeExtensions.contains(document.fileExtension.lowercased())
    }
}

// MARK: - PDFKit bridge

/// Strips the PDFKit chrome down to just the page surface — no thumbnails,
/// no scrollbar bumps. Sized to the host frame; PDFKit handles its own
/// internal scrolling for multi-page docs.
private struct PDFInlineRepresentable: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.pageShadowsEnabled = false
        view.minScaleFactor = 0.25
        view.maxScaleFactor = 4.0
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
            nsView.autoScales = true
        }
    }
}
