import SwiftUI

// MARK: - RichMessage
//
// NotebookLM-style block-aware renderer for assistant messages. Splits the
// LLM's text into headings / paragraphs / bullets / numbered items, indents
// nested lists, renders **bold** and *italic* per-word, and embeds the
// existing CitationPill mid-line for `[N]` tokens.
//
// We deliberately do this ourselves rather than reaching for `AttributedString
// (markdown:)`: that renders a *single rigid Text block*, which means our
// clickable, hover-preview citation pills can't sit between words. The
// per-word FlowLayout pass is the trade-off that lets bold + inline pills
// coexist with natural word wrapping.

struct RichMessage: View {
    let text: String
    let sources: [RAGSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let blocks = Self.parseBlocks(text)
            ForEach(blocks.indices, id: \.self) { i in
                blockView(blocks[i])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let inline):
            inlineFlow(inline)
                .font(.system(
                    size: level == 1 ? 18 : (level == 2 ? 15 : 13),
                    weight: .semibold,
                    design: .serif
                ))
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
                .padding(.top, level <= 2 ? 4 : 0)

        case .paragraph(let inline):
            inlineFlow(inline)

        case .bullet(let indent, let inline):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Japandi.Colors.accentMutedFallback)
                    .padding(.leading, CGFloat(indent) * 14)
                inlineFlow(inline)
            }

        case .numbered(let indent, let number, let inline):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(number)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Japandi.Colors.accentFallback)
                    .frame(minWidth: 18, alignment: .trailing)
                    .padding(.leading, CGFloat(indent) * 14)
                inlineFlow(inline)
            }
        }
    }

    /// Each block's inline content flows through FlowLayout so words wrap
    /// naturally next to citation pills.
    private func inlineFlow(_ runs: [InlineRun]) -> some View {
        FlowLayout(spacing: 0) {
            ForEach(runs.indices, id: \.self) { i in
                switch runs[i] {
                case .word(let w, let style):
                    Text(w)
                        .font(font(for: style))
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                case .space:
                    Text(" ").font(Japandi.Typography.body)
                case .citation(let n):
                    CitationPill(number: n, source: source(at: n))
                        .padding(.leading, 1)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func font(for style: InlineStyle) -> Font {
        switch style {
        case .normal: Japandi.Typography.body
        case .bold:   .system(size: 13, weight: .semibold, design: .default)
        case .italic: .system(size: 13, weight: .regular, design: .default).italic()
        case .boldItalic: .system(size: 13, weight: .semibold, design: .default).italic()
        }
    }

    private func source(at index: Int) -> RAGSource? {
        guard index >= 1, index <= sources.count else { return nil }
        return sources[index - 1]
    }

    // MARK: - Block model

    enum Block {
        case heading(level: Int, [InlineRun])
        case paragraph([InlineRun])
        case bullet(indent: Int, [InlineRun])
        case numbered(indent: Int, number: String, [InlineRun])
    }

    enum InlineStyle: Hashable {
        case normal, bold, italic, boldItalic
    }

    enum InlineRun: Hashable {
        case word(String, InlineStyle)
        case space
        case citation(Int)
    }

    // MARK: - Block parsing

    /// Walk the message line by line, classify each line as heading / list /
    /// paragraph, and accumulate consecutive paragraph lines into a single
    /// run so prose reads as one wrapped chunk instead of one block per line.
    static func parseBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            if !paragraphBuffer.isEmpty {
                let joined = paragraphBuffer.joined(separator: " ")
                let runs = parseInline(joined)
                if !runs.isEmpty {
                    blocks.append(.paragraph(runs))
                }
                paragraphBuffer.removeAll()
            }
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for raw in lines {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line → flush the current paragraph.
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            // Heading: ###, ##, # (with at least one space after the hash run)
            if let level = headingLevel(trimmed) {
                flushParagraph()
                let body = String(trimmed.drop(while: { $0 == "#" }))
                    .trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: level, parseInline(body)))
                continue
            }

            // Bullet: -, *, • (indented by N spaces). Note: we accept up to 8
            // levels but cap visual indent at 4 to avoid runaway formatting.
            if let (indent, content) = matchBullet(line) {
                flushParagraph()
                blocks.append(.bullet(indent: min(indent, 4), parseInline(content)))
                continue
            }

            // Numbered list: 1. or 1) (optionally indented).
            if let (indent, number, content) = matchNumbered(line) {
                flushParagraph()
                blocks.append(.numbered(indent: min(indent, 4), number: number, parseInline(content)))
                continue
            }

            // Otherwise it's a paragraph line — accumulate.
            paragraphBuffer.append(trimmed)
        }
        flushParagraph()
        return blocks
    }

    private static func headingLevel(_ trimmed: String) -> Int? {
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 3 else { return nil }
        let afterHashes = trimmed.dropFirst(hashes)
        guard afterHashes.first == " " else { return nil }
        return hashes
    }

    private static func matchBullet(_ line: String) -> (indent: Int, content: String)? {
        let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
        let indent = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
        let rest = String(line.dropFirst(leading.count))
        guard let first = rest.first else { return nil }
        let bulletChars: Set<Character> = ["-", "*", "•", "·"]
        guard bulletChars.contains(first), rest.count >= 2 else { return nil }
        let afterMarker = rest.dropFirst()
        guard afterMarker.first == " " else { return nil }
        return (indent, String(afterMarker.drop(while: { $0 == " " })))
    }

    private static func matchNumbered(_ line: String) -> (indent: Int, number: String, content: String)? {
        let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
        let indent = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
        let rest = String(line.dropFirst(leading.count))
        // Match: <digits>(.|)) <space>
        var i = rest.startIndex
        while i < rest.endIndex, rest[i].isNumber { i = rest.index(after: i) }
        guard i != rest.startIndex, i < rest.endIndex else { return nil }
        let punct = rest[i]
        guard punct == "." || punct == ")" else { return nil }
        let afterPunct = rest.index(after: i)
        guard afterPunct < rest.endIndex, rest[afterPunct] == " " else { return nil }
        let numberStr = String(rest[..<i]) + "."
        let content = String(rest[afterPunct...]).drop(while: { $0 == " " })
        return (indent, numberStr, String(content))
    }

    // MARK: - Inline parsing

    /// Pattern matches `[1]`, `[Source 1]`, `[src 1]`. Same shape as the
    /// CitationText regex so behaviour is consistent across both renderers.
    private static let citationRegex = /\[(?:[Ss]ource\s*|[Ss]rc\s*)?(\d{1,3})\]/

    /// Split a single line into words, spaces, and citations, with per-word
    /// bold/italic styling derived from `**...**` and `*...*` markers.
    static func parseInline(_ text: String) -> [InlineRun] {
        // Pull out citation ranges first; they're not eligible for bold/italic.
        let citationMatches: [(Range<String.Index>, Int)] = text
            .matches(of: citationRegex)
            .compactMap { m -> (Range<String.Index>, Int)? in
                guard let n = Int(String(m.output.1)) else { return nil }
                return (m.range, n)
            }

        var runs: [InlineRun] = []
        var cursor = text.startIndex
        for (range, number) in citationMatches {
            if cursor < range.lowerBound {
                runs.append(contentsOf: wordRunsWithStyle(String(text[cursor..<range.lowerBound])))
            }
            runs.append(.citation(number))
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            runs.append(contentsOf: wordRunsWithStyle(String(text[cursor..<text.endIndex])))
        }
        return runs
    }

    /// Split a stretch of prose into word + space runs, tagging each word
    /// with the bold/italic state that's active when we walk over it. We use
    /// a tiny hand-rolled state machine because Markdown's emphasis rules
    /// have a few corner cases (`**bold *and italic***`) that we don't need
    /// to handle perfectly — the LLM output is well-behaved.
    private static func wordRunsWithStyle(_ text: String) -> [InlineRun] {
        var out: [InlineRun] = []
        var bold = false
        var italic = false
        var pending = ""

        func currentStyle() -> InlineStyle {
            switch (bold, italic) {
            case (true, true):   return .boldItalic
            case (true, false):  return .bold
            case (false, true):  return .italic
            case (false, false): return .normal
            }
        }

        func flushWord() {
            if !pending.isEmpty {
                out.append(.word(pending, currentStyle()))
                pending = ""
            }
        }

        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            let next = text.index(after: i)

            // Bold marker: **
            if c == "*", next < text.endIndex, text[next] == "*" {
                flushWord()
                bold.toggle()
                i = text.index(after: next)
                continue
            }
            // Italic marker: *  (not part of **)
            if c == "*" {
                flushWord()
                italic.toggle()
                i = next
                continue
            }
            // Space terminates a word.
            if c == " " {
                flushWord()
                out.append(.space)
                i = next
                continue
            }
            pending.append(c)
            i = next
        }
        flushWord()
        return out
    }
}
