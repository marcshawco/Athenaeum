import SwiftUI
import SwiftData

struct ChatView: View {
    var llmService: LLMServiceProtocol
    var ragService: RAGService
    @Query(sort: \Document.importedAt, order: .reverse) private var documents: [Document]
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isGenerating = false
    @State private var streamedResponse: String = ""
    @State private var currentSources: [RAGSource] = []
    @State private var showSources = false
    @State private var generationTask: Task<Void, Never>?
    @State private var hasAttemptedIndexRepair = false
    @State private var indexedDocumentIDs: Set<UUID> = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: Japandi.Spacing.md) {
                VStack(alignment: .leading, spacing: Japandi.Spacing.xxs) {
                    Text("Local RAG")
                        .eyebrowStyle(Japandi.Colors.accentFallback)

                    Text("Document Chat")
                        .font(Japandi.Typography.title)
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    Text("Ask questions with private retrieval over your indexed archive.")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
                Spacer()

                if !currentSources.isEmpty {
                    Button {
                        withAnimation(Japandi.Motion.snappy) { showSources.toggle() }
                    } label: {
                        HStack(spacing: Japandi.Spacing.xxs) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 10, weight: .light))
                            Text("\(currentSources.count) sources")
                                .font(Japandi.Typography.caption)
                        }
                        .foregroundStyle(Japandi.Colors.accentFallback)
                        .padding(.horizontal, Japandi.Spacing.xs)
                        .padding(.vertical, Japandi.Spacing.xxs + 1)
                        .background(Japandi.Colors.accentFallback.opacity(0.06))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Japandi.Colors.accentFallback.opacity(0.2), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    stopGeneration(keepingPartialResponse: false)
                    messages.removeAll()
                    streamedResponse = ""
                    currentSources = []
                    showSources = false
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
                .buttonStyle(.plain)
                .disabled(messages.isEmpty)
            }
            .padding(.horizontal, Japandi.Spacing.lg)
            .padding(.vertical, Japandi.Spacing.md)

            Rectangle()
                .fill(Japandi.Colors.borderFallback.opacity(0.8))
                .frame(height: 0.5)

            // Main content
            HSplitView {
                messagesColumn

                if showSources && !currentSources.isEmpty {
                    sourcesPanel
                        .frame(minWidth: 200, idealWidth: 260, maxWidth: 320)
                }
            }

            Rectangle()
                .fill(Japandi.Colors.borderFallback.opacity(0.8))
                .frame(height: 0.5)

            inputBar
        }
        .background(Japandi.Colors.bgFallback)
        .task {
            await repairIndexIfNeeded()
        }
    }

    // MARK: - Messages Column

    private var messagesColumn: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Japandi.Spacing.md) {
                    if messages.isEmpty {
                        chatEmptyState
                    }

                    ForEach(messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }

                    if !streamedResponse.isEmpty {
                        ChatBubble(message: ChatMessage(role: .assistant, content: streamedResponse))
                            .id("streaming")
                    }

                    if isGenerating && streamedResponse.isEmpty {
                        HStack(spacing: Japandi.Spacing.xs) {
                            ProgressView()
                                .scaleEffect(0.55)
                            Text("Searching documents...")
                                .font(Japandi.Typography.caption)
                                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                        }
                        .padding(.leading, Japandi.Spacing.sm)
                    }
                }
                .padding(Japandi.Spacing.md)
            }
            .onChange(of: messages.count) {
                withAnimation {
                    proxy.scrollTo(messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: streamedResponse) {
                withAnimation {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Sources Panel

    private var sourcesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sources")
                    .font(Japandi.Typography.headline)
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                Spacer()
                Button {
                    withAnimation(Japandi.Motion.snappy) { showSources = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Japandi.Spacing.md)
            .padding(.vertical, Japandi.Spacing.sm)

            Rectangle()
                .fill(Japandi.Colors.borderFallback.opacity(0.8))
                .frame(height: 0.5)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
                    ForEach(currentSources) { source in
                        SourceCard(source: source)
                    }
                }
                .padding(Japandi.Spacing.sm)
            }
        }
        .background(Japandi.Colors.surfaceFallback.opacity(0.6))
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: Japandi.Spacing.sm) {
            TextField("Ask about your documents...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Japandi.Typography.body)
                .lineLimit(1...5)
                .onSubmit { if !isGenerating { sendMessage() } }
                .focused($isInputFocused)

            Button {
                if isGenerating {
                    stopGeneration()
                } else {
                    sendMessage()
                }
            } label: {
                Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        inputText.isEmpty && !isGenerating
                            ? Japandi.Colors.borderFallback
                            : Japandi.Colors.accentFallback
                    )
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty && !isGenerating)
        }
        .padding(.horizontal, Japandi.Spacing.md)
        .padding(.vertical, Japandi.Spacing.sm)
        .background(Japandi.Colors.surfaceRaisedFB)
    }

    // MARK: - Empty State

    private var chatEmptyState: some View {
        VStack(spacing: Japandi.Spacing.xl) {
            Spacer(minLength: Japandi.Spacing.xxxl)

            ZStack {
                RoundedRectangle(cornerRadius: Japandi.Radius.lg, style: .continuous)
                    .fill(Japandi.Colors.inkFallback.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: Japandi.Radius.lg, style: .continuous)
                            .strokeBorder(Japandi.Colors.inkFallback.opacity(0.2), lineWidth: 0.5)
                    )
                    .frame(width: 60, height: 60)
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 22, weight: .ultraLight))
                    .foregroundStyle(Japandi.Colors.accentFallback)
            }

            VStack(spacing: Japandi.Spacing.xs) {
                Text("Chat with your documents")
                    .font(Japandi.Typography.title)
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)

                Text("Questions are answered from imported document text with local retrieval when available")
                    .font(Japandi.Typography.body)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            VStack(spacing: Japandi.Spacing.xs) {
                SuggestedPrompt(text: "Summarize my most recent document") {
                    inputText = "Summarize my most recent document"
                    sendMessage()
                }
                SuggestedPrompt(text: "What invoices do I have from this month?") {
                    inputText = "What invoices do I have from this month?"
                    sendMessage()
                }
                SuggestedPrompt(text: "Find documents related to...") {
                    inputText = "Find documents related to "
                }
            }

            Spacer(minLength: Japandi.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        let history = messages
        let fallbackDocuments = documentContexts
        messages.append(userMessage)
        inputText = ""
        isGenerating = true
        streamedResponse = ""

        generationTask = Task {
            defer {
                isGenerating = false
                generationTask = nil
                isInputFocused = true
            }

            do {
                await repairIndexIfNeeded()
                let (stream, sources) = try await ragService.queryStream(
                    text,
                    history: history,
                    maxContext: 8,
                    fallbackDocuments: fallbackDocuments
                )
                currentSources = sources
                if !sources.isEmpty {
                    withAnimation(Japandi.Motion.snappy) { showSources = true }
                }

                for try await token in stream {
                    try Task.checkCancellation()
                    let candidate = streamedResponse + token

                    if let stopRange = candidate.range(of: "<|im_end|>") {
                        streamedResponse = String(candidate[..<stopRange.lowerBound])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                    if let stopRange = candidate.range(of: "<|im_start|>") {
                        streamedResponse = String(candidate[..<stopRange.lowerBound])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }

                    streamedResponse = candidate
                }

                let finalContent = streamedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                let response = ChatMessage(role: .assistant, content: finalContent.isEmpty ? "(no response)" : finalContent)
                messages.append(response)
                streamedResponse = ""
            } catch is CancellationError {
                let partial = streamedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                if !partial.isEmpty {
                    messages.append(ChatMessage(role: .assistant, content: partial))
                    streamedResponse = ""
                }
            } catch {
                let errorMsg = ChatMessage(role: .assistant, content: "⚠️ \(error.localizedDescription)")
                messages.append(errorMsg)
                streamedResponse = ""
            }
        }
    }

    private func stopGeneration(keepingPartialResponse: Bool = true) {
        generationTask?.cancel()
        generationTask = nil

        if keepingPartialResponse {
            let partial = streamedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            if !partial.isEmpty {
                messages.append(ChatMessage(role: .assistant, content: partial))
            }
        }

        streamedResponse = ""
        isGenerating = false
        isInputFocused = true
    }

    private var documentContexts: [RAGDocumentContext] {
        documents.compactMap { document in
            guard document.processingStatus == .complete,
                  let text = document.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }

            return RAGDocumentContext(
                id: document.id,
                title: document.title,
                text: text,
                documentDate: document.documentDate,
                importedAt: document.importedAt
            )
        }
    }

    private func repairIndexIfNeeded() async {
        for context in documentContexts {
            guard !indexedDocumentIDs.contains(context.id) || !hasAttemptedIndexRepair else { continue }
            try? await ragService.indexDocument(id: context.id, text: context.text)
            indexedDocumentIDs.insert(context.id)
        }
        hasAttemptedIndexRepair = true
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: Japandi.Spacing.xxl) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: Japandi.Spacing.xxxs) {
                Text(message.content)
                    .font(Japandi.Typography.body)
                    .foregroundStyle(isUser ? .white : Japandi.Colors.textPrimaryFB)
                    .textSelection(.enabled)

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9))
                    .foregroundStyle(
                        isUser
                            ? Color.white.opacity(0.5)
                            : Japandi.Colors.textTertiaryFB
                    )
            }
            .padding(.horizontal, Japandi.Spacing.md)
            .padding(.vertical, Japandi.Spacing.sm)
            .background(
                isUser
                    ? Japandi.Colors.inkFallback
                    : Japandi.Colors.surfaceRaisedFB
            )
            .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Japandi.Radius.md, style: .continuous)
                    .strokeBorder(
                        isUser
                            ? Color.white.opacity(0.06)
                            : Japandi.Colors.borderFallback.opacity(0.85),
                        lineWidth: 0.5
                    )
            )
            .japandiShadow(Japandi.Shadow.subtle)

            if !isUser { Spacer(minLength: Japandi.Spacing.xxl) }
        }
    }
}

// MARK: - Source Card

struct SourceCard: View {
    let source: RAGSource

    var body: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.xxs) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.system(size: 9, weight: .light))
                    .foregroundStyle(Japandi.Colors.accentMutedFallback)

                if let page = source.pageNumber {
                    Text("Page \(page)")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textSecondaryFB)
                } else if let title = source.documentTitle {
                    Text(title)
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textSecondaryFB)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(source.relevancePercent)%")
                    .font(Japandi.Typography.eyebrow)
                    .foregroundStyle(Japandi.Colors.accentFallback)
            }

            Text(source.chunkText)
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)
                .lineLimit(4)
        }
        .padding(Japandi.Spacing.xs)
        .background(Japandi.Colors.surfaceRaisedFB)
        .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous)
                .strokeBorder(Japandi.Colors.borderFallback.opacity(0.85), lineWidth: 0.5)
        )
    }
}

// MARK: - Suggested Prompt Button

struct SuggestedPrompt: View {
    let text: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)
                .padding(.horizontal, Japandi.Spacing.md)
                .padding(.vertical, Japandi.Spacing.xs)
                .frame(maxWidth: 300, alignment: .leading)
                .background(
                    isHovered
                        ? Japandi.Colors.surfaceFallback
                        : Japandi.Colors.surfaceRaisedFB
                )
                .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous)
                        .strokeBorder(Japandi.Colors.borderFallback.opacity(0.85), lineWidth: 0.5)
                )
                .animation(Japandi.Motion.snappy, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
