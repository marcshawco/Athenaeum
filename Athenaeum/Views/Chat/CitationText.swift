import SwiftUI

// MARK: - CitationText
//
// NotebookLM-style inline citations. The model emits citation tokens like
// `[1]`, `[2]`, `[1][3]` etc. We split the prose into word + citation runs,
// flow them through `FlowLayout`, and render citations as compact, clickable
// numbered pills. The text wraps naturally and the pills wrap with it.
//
// Why per-word: SwiftUI's `Text` is a rigid block — it wraps but it can't
// embed live, hover-aware, individually clickable subviews. To get clickable
// pills mid-paragraph we have to flow word-sized runs ourselves.

struct CitationText: View {
    let text: String
    let sources: [RAGSource]

    /// Pattern matches:
    ///   [1]         single citation
    ///   [1][3]      adjacent citations (treated as separate matches)
    ///   [Source 2]  defensive — older models still emit this; we strip it.
    /// Captured group 1 is the integer index.
    private static let citationRegex = /\[(?:[Ss]ource\s*|[Ss]rc\s*)?(\d{1,3})\]/

    var body: some View {
        let runs = Self.tokenize(text)
        FlowLayout(spacing: 0) {
            ForEach(runs.indices, id: \.self) { i in
                switch runs[i] {
                case .word(let w):
                    Text(w)
                        .font(Japandi.Typography.body)
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                case .space:
                    // Use a transparent space char so FlowLayout still picks
                    // up width but lines wrap cleanly.
                    Text(" ")
                        .font(Japandi.Typography.body)
                case .newline:
                    // Sentinel "newline" token — forces a hard break by
                    // taking a full-width "space" before continuing.
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                case .citation(let n):
                    CitationPill(number: n, source: source(at: n))
                        .padding(.leading, 1)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func source(at index: Int) -> RAGSource? {
        guard index >= 1, index <= sources.count else { return nil }
        return sources[index - 1]
    }

    // MARK: - Tokenization

    enum Run: Hashable {
        case word(String)
        case space
        case newline
        case citation(Int)
    }

    /// Split `text` into a flat run of words / spaces / newlines / citations.
    /// Multi-character citation runs like `[1][3]` produce two adjacent
    /// `.citation` runs with no space between them.
    static func tokenize(_ text: String) -> [Run] {
        var runs: [Run] = []
        var cursor = text.startIndex
        let end = text.endIndex

        // Find every citation match up front.
        let matches: [(Range<String.Index>, Int)] = text
            .matches(of: citationRegex)
            .compactMap { m -> (Range<String.Index>, Int)? in
                let captured = String(m.output.1)
                guard let n = Int(captured) else { return nil }
                return (m.range, n)
            }

        for (range, number) in matches {
            // Emit any prose between the last cursor and this citation.
            if cursor < range.lowerBound {
                let slice = String(text[cursor..<range.lowerBound])
                runs.append(contentsOf: wordRuns(in: slice))
            }
            runs.append(.citation(number))
            cursor = range.upperBound
        }
        // Tail prose.
        if cursor < end {
            runs.append(contentsOf: wordRuns(in: String(text[cursor..<end])))
        }
        return runs
    }

    /// Split a stretch of prose into word + space runs while preserving
    /// hard newlines.
    private static func wordRuns(in text: String) -> [Run] {
        var out: [Run] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (lineIdx, line) in lines.enumerated() {
            let words = line.split(separator: " ", omittingEmptySubsequences: false)
            for (i, w) in words.enumerated() {
                if w.isEmpty {
                    if i > 0 { out.append(.space) }
                } else {
                    out.append(.word(String(w)))
                    if i < words.count - 1 { out.append(.space) }
                }
            }
            if lineIdx < lines.count - 1 {
                out.append(.newline)
            }
        }
        return out
    }
}

// MARK: - CitationPill

/// Small numbered circle that sits inline with the prose. Looks like
/// NotebookLM's superscript chip. Click opens a popover preview with the
/// document title + chunk excerpt + an explicit "View source" link, so the
/// user stays in their chat by default and only navigates when they ask to.
struct CitationPill: View {
    let number: Int
    let source: RAGSource?

    @State private var isHovered = false
    @State private var showPreview = false

    var body: some View {
        Button {
            guard source != nil else { return }
            showPreview.toggle()
        } label: {
            Text("\(number)")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(isHovered || showPreview
                                 ? Japandi.Colors.surfaceFallback
                                 : Japandi.Colors.accentFallback)
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(isHovered || showPreview
                              ? Japandi.Colors.accentFallback
                              : Japandi.Colors.washFallback)
                        .overlay(
                            Circle().strokeBorder(
                                Japandi.Colors.accentFallback.opacity((isHovered || showPreview) ? 0.0 : 0.35),
                                lineWidth: 0.5
                            )
                        )
                )
                .padding(.horizontal, 1)
                .baselineOffset(2)
        }
        .buttonStyle(.plain)
        .disabled(source == nil)
        .onHover { isHovered = $0 }
        .help(source.map { "Preview \($0.documentTitle ?? "source")" } ?? "Source not available")
        .accessibilityLabel("Citation \(number)")
        .popover(isPresented: $showPreview, arrowEdge: .top) {
            if let source {
                CitationPreviewPopover(source: source, number: number) {
                    showPreview = false
                    NotificationCenter.default.post(
                        name: .selectDocumentByID,
                        object: nil,
                        userInfo: ["documentID": source.documentID]
                    )
                }
            }
        }
    }
}

// MARK: - Popover

/// The hover-card NotebookLM shows when you tap a citation: numbered chip,
/// document title, snippet, and a "View source" link to actually open the
/// document. Sized to feel like a tooltip rather than a dialog.
private struct CitationPreviewPopover: View {
    let source: RAGSource
    let number: Int
    let onViewSource: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
            HStack(alignment: .center, spacing: Japandi.Spacing.xs) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Japandi.Colors.accentFallback)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(Japandi.Colors.washFallback)
                            .overlay(Circle().strokeBorder(Japandi.Colors.accentFallback.opacity(0.35), lineWidth: 0.5))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.documentTitle ?? "Untitled document")
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        if let page = source.pageNumber {
                            Text("Page \(page)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                            Text("·")
                                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                        }
                        Text("\(source.relevancePercent)% match")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Japandi.Colors.accentFallback)
                    }
                }
                Spacer(minLength: 0)
            }

            Divider().foregroundStyle(Japandi.Colors.borderFallback)

            ScrollView {
                Text(source.chunkText)
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)

            Divider().foregroundStyle(Japandi.Colors.borderFallback)

            Button(action: onViewSource) {
                HStack(spacing: 4) {
                    Text("View source")
                        .font(Japandi.Typography.body)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Japandi.Colors.accentFallback)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open source document")
        }
        .padding(Japandi.Spacing.md)
        .frame(width: 360)
        .background(Japandi.Colors.surfaceRaisedFB)
    }
}
