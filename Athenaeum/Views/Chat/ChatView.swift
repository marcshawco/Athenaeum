import SwiftUI
import SwiftData

struct ChatView: View {
    var llmService: LLMServiceProtocol
    var ragService: RAGService
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Document.importedAt, order: .reverse) private var documents: [Document]
    /// Persisted conversations, newest first. Drives the history popover.
    @Query(sort: \ChatConversation.modifiedAt, order: .reverse)
    private var conversations: [ChatConversation]

    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isGenerating = false
    @State private var streamedResponse: String = ""
    @State private var currentSources: [RAGSource] = []
    @State private var showSources = false
    /// Sources retrieved for each assistant turn, keyed by message id. Lets
    /// each message render its own compact "Sources used" disclosure so the
    /// citations are traceable per turn rather than only globally.
    @State private var sourcesByMessage: [UUID: [RAGSource]] = [:]
    @State private var expandedSourcesByMessage: Set<UUID> = []
    @State private var generationTask: Task<Void, Never>?
    @State private var hasAttemptedIndexRepair = false
    @State private var indexedDocumentIDs: Set<UUID> = []
    @FocusState private var isInputFocused: Bool

    /// The currently-open conversation. Created lazily on the first user
    /// turn so an empty chat surface doesn't litter the history list.
    @State private var currentConversationID: UUID?
    @State private var showHistoryPopover = false
    @State private var renameTargetID: UUID?
    @State private var renameText: String = ""
    @State private var showClearConfirm = false
    @State private var hasRestoredOnAppear = false

    /// Survives across navigation (citation click → library → back to chat)
    /// so the same conversation re-opens instead of resetting to empty.
    @AppStorage("currentChatID") private var storedChatIDRaw: String = ""

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

                // History popover — list of past conversations.
                Button {
                    showHistoryPopover = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10, weight: .light))
                        Text("History")
                            .font(Japandi.Typography.caption)
                    }
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                    .padding(.horizontal, Japandi.Spacing.xs)
                    .padding(.vertical, Japandi.Spacing.xxs + 1)
                    .background(Japandi.Colors.surfaceRaisedFB)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Japandi.Colors.borderFallback, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Open chat history")
                .accessibilityLabel("Chat history")
                .popover(isPresented: $showHistoryPopover, arrowEdge: .top) {
                    chatHistoryPopover
                }

                // New chat — saves current and starts fresh.
                Button {
                    startNewConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(Japandi.Colors.textSecondaryFB)
                }
                .buttonStyle(.plain)
                .help("New chat")
                .accessibilityLabel("New chat")

                // Clear chat — destructive. Wipes the current conversation
                // from history entirely. Distinct from "New chat" because
                // it does NOT preserve the current chat in history.
                Button {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(Japandi.Colors.warmFallback)
                }
                .buttonStyle(.plain)
                .help("Clear this chat")
                .accessibilityLabel("Clear chat")
                .disabled(messages.isEmpty && currentConversationID == nil)
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
        .onAppear {
            // Restore the most recent conversation the first time the view
            // appears in this lifetime. Citation clicks → library → return
            // here will re-enter this branch and reload the chat the user
            // left, rather than presenting an empty screen.
            guard !hasRestoredOnAppear else { return }
            hasRestoredOnAppear = true
            restoreLastConversation()
        }
        .confirmationDialog(
            "Clear this chat?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear chat", role: .destructive) { clearCurrentChat() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes the current conversation from history. Other saved chats are untouched.")
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
                        VStack(alignment: .leading, spacing: Japandi.Spacing.xxs) {
                            ChatBubble(
                                message: message,
                                sources: sourcesByMessage[message.id] ?? []
                            )
                            if let perMessageSources = sourcesByMessage[message.id], !perMessageSources.isEmpty {
                                inlineSourcesDisclosure(messageID: message.id, sources: perMessageSources)
                            }
                        }
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

    // MARK: - Inline sources (per assistant turn)

    /// Compact "Sources used" row anchored beneath each assistant message.
    /// Tappable disclosure that expands to show the same SourceCard rows
    /// the global side-panel uses. Lets users audit citations per turn
    /// without having to keep the right-hand panel open.
    @ViewBuilder
    private func inlineSourcesDisclosure(messageID: UUID, sources: [RAGSource]) -> some View {
        let isOpen = expandedSourcesByMessage.contains(messageID)
        VStack(alignment: .leading, spacing: Japandi.Spacing.xxs) {
            Button {
                if isOpen { expandedSourcesByMessage.remove(messageID) }
                else      { expandedSourcesByMessage.insert(messageID) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Japandi.Colors.accentFallback)
                    Text("\(sources.count) source\(sources.count == 1 ? "" : "s") used")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.accentFallback)
                    if !isOpen {
                        Text("·")
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                        Text(sources.prefix(2).map { $0.documentTitle ?? "(untitled)" }.joined(separator: " · "))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOpen ? "Hide sources used" : "Show sources used")

            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { idx, source in
                        SourceCard(source: source, index: idx + 1)
                    }
                }
                .padding(.leading, 14)
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.leading, Japandi.Spacing.sm)
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
                    ForEach(Array(currentSources.enumerated()), id: \.element.id) { idx, source in
                        SourceCard(source: source, index: idx + 1)
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
        // Materialize the conversation on first send and persist the user
        // turn immediately so a crash mid-generation doesn't lose the input.
        ensureCurrentConversation()
        saveCurrentConversation()

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
                if !sources.isEmpty {
                    sourcesByMessage[response.id] = sources
                }
                streamedResponse = ""
                saveCurrentConversation()
            } catch is CancellationError {
                let partial = streamedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                if !partial.isEmpty {
                    messages.append(ChatMessage(role: .assistant, content: partial))
                    streamedResponse = ""
                }
                saveCurrentConversation()
            } catch {
                let errorMsg = ChatMessage(role: .assistant, content: "⚠️ \(error.localizedDescription)")
                messages.append(errorMsg)
                streamedResponse = ""
                saveCurrentConversation()
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

    // MARK: - Chat history popover

    private var chatHistoryPopover: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chats")
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                Spacer()
                Text("\(conversations.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }
            .padding(.horizontal, Japandi.Spacing.sm)
            .padding(.vertical, 8)

            Divider().foregroundStyle(Japandi.Colors.borderFallback)

            if conversations.isEmpty {
                VStack(spacing: Japandi.Spacing.xs) {
                    Image(systemName: "tray")
                        .font(.system(size: 22, weight: .ultraLight))
                        .foregroundStyle(Japandi.Colors.borderFallback)
                    Text("No saved chats yet")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Japandi.Spacing.lg)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(conversations) { conv in
                            historyRow(conv)
                            Divider().foregroundStyle(Japandi.Colors.borderFallback.opacity(0.4))
                        }
                    }
                }
                .frame(maxHeight: 360)
            }

            Divider().foregroundStyle(Japandi.Colors.borderFallback)

            Button {
                showHistoryPopover = false
                startNewConversation()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11))
                    Text("New chat")
                        .font(Japandi.Typography.body)
                }
                .foregroundStyle(Japandi.Colors.accentFallback)
                .padding(.horizontal, Japandi.Spacing.sm)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 320)
        .background(Japandi.Colors.surfaceRaisedFB)
    }

    private func historyRow(_ conv: ChatConversation) -> some View {
        let isCurrent = currentConversationID == conv.id
        let isRenaming = renameTargetID == conv.id
        return HStack(alignment: .top, spacing: Japandi.Spacing.xs) {
            // Active dot
            Circle()
                .fill(isCurrent ? Japandi.Colors.accentFallback : Color.clear)
                .frame(width: 5, height: 5)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("Title", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                        .onSubmit { commitRename(conv) }
                } else {
                    Text(conv.title)
                        .font(.system(size: 12.5, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                        .lineLimit(1)
                }
                Text(conv.preview)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    .lineLimit(1)
                Text(conv.modifiedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Japandi.Spacing.sm)
        .padding(.vertical, 8)
        .background(isCurrent
                    ? Japandi.Colors.washFallback.opacity(0.6)
                    : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isRenaming else { return }
            load(conv)
            showHistoryPopover = false
        }
        .contextMenu {
            Button {
                renameTargetID = conv.id
                renameText = conv.title
            } label: { Label("Rename", systemImage: "pencil") }

            Button {
                duplicate(conv)
            } label: { Label("Duplicate", systemImage: "doc.on.doc") }

            Divider()

            Button(role: .destructive) {
                delete(conv)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: - Persistence

    /// Find or create the conversation matching `currentConversationID`.
    /// Called lazily so that landing on the chat surface doesn't create a
    /// row in the history list until the user actually sends a message.
    @discardableResult
    private func ensureCurrentConversation() -> ChatConversation {
        if let id = currentConversationID,
           let existing = conversations.first(where: { $0.id == id }) {
            return existing
        }
        let conv = ChatConversation(title: "New chat")
        modelContext.insert(conv)
        try? modelContext.save()
        currentConversationID = conv.id
        storedChatIDRaw = conv.id.uuidString
        return conv
    }

    /// On first appearance, re-hydrate the conversation the user was last in.
    /// Priority: the explicit `currentChatID` AppStorage, then the most
    /// recently modified chat that actually has content. Falls through to
    /// the empty default if there's nothing to restore.
    private func restoreLastConversation() {
        if !messages.isEmpty { return }   // already loaded in-memory
        if let uuid = UUID(uuidString: storedChatIDRaw),
           let saved = conversations.first(where: { $0.id == uuid }) {
            load(saved)
            return
        }
        if let recent = conversations.first(where: { !$0.storedMessages().isEmpty }) {
            load(recent)
        }
    }

    /// Snapshot the in-memory message list onto the active conversation. We
    /// rewrite the whole JSON blob each time — cheap, and avoids per-message
    /// SwiftData inserts. Also derives a title from the first user message
    /// when the conversation is still called "New chat".
    private func saveCurrentConversation() {
        guard let id = currentConversationID,
              let conv = conversations.first(where: { $0.id == id }) else { return }
        let stored = messages.map { msg in
            StoredMessage(
                from: msg,
                sources: sourcesByMessage[msg.id] ?? []
            )
        }
        conv.setStoredMessages(stored)
        if conv.title == "New chat",
           let firstUser = messages.first(where: { $0.role == .user })?.content {
            conv.title = String(firstUser.prefix(60))
        }
        try? modelContext.save()
    }

    /// Reset transient state and load a persisted conversation's messages
    /// into the live view. Stops any in-flight generation first.
    private func load(_ conv: ChatConversation) {
        stopGeneration(keepingPartialResponse: false)
        let stored = conv.storedMessages()
        messages = stored.map(\.chatMessage)
        sourcesByMessage = Dictionary(
            uniqueKeysWithValues: stored.compactMap { s -> (UUID, [RAGSource])? in
                guard !s.sources.isEmpty else { return nil }
                return (s.id, s.ragSources)
            }
        )
        // Restore the most-recent assistant turn's sources so the side panel
        // and the "N sources" pill in the header reflect the loaded chat.
        if let lastAssistant = messages.last(where: { $0.role == .assistant }) {
            currentSources = sourcesByMessage[lastAssistant.id] ?? []
        } else {
            currentSources = []
        }
        streamedResponse = ""
        currentConversationID = conv.id
        storedChatIDRaw = conv.id.uuidString
    }

    /// Persist the current chat (if it has any messages) and start a fresh,
    /// empty conversation. The new row is created lazily on the next send.
    private func startNewConversation() {
        if !messages.isEmpty { saveCurrentConversation() }
        stopGeneration(keepingPartialResponse: false)
        messages.removeAll()
        sourcesByMessage.removeAll()
        expandedSourcesByMessage.removeAll()
        currentSources = []
        showSources = false
        streamedResponse = ""
        currentConversationID = nil
        storedChatIDRaw = ""
    }

    /// Destructive: wipe the current conversation entirely (drop from
    /// SwiftData + reset in-memory state). Other chats in history stay put.
    /// Wired behind a confirmation dialog so it can't fire by accident.
    private func clearCurrentChat() {
        if let id = currentConversationID,
           let conv = conversations.first(where: { $0.id == id }) {
            modelContext.delete(conv)
            try? modelContext.save()
        }
        stopGeneration(keepingPartialResponse: false)
        messages.removeAll()
        sourcesByMessage.removeAll()
        expandedSourcesByMessage.removeAll()
        currentSources = []
        showSources = false
        streamedResponse = ""
        currentConversationID = nil
        storedChatIDRaw = ""
    }

    private func delete(_ conv: ChatConversation) {
        let wasCurrent = (currentConversationID == conv.id)
        modelContext.delete(conv)
        try? modelContext.save()
        if wasCurrent { startNewConversation() }
    }

    private func duplicate(_ conv: ChatConversation) {
        let copy = ChatConversation(title: conv.title + " copy")
        copy.messagesJSON = conv.messagesJSON
        copy.modifiedAt = .now
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func commitRename(_ conv: ChatConversation) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { conv.title = trimmed }
        try? modelContext.save()
        renameTargetID = nil
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
    var sources: [RAGSource] = []

    private var isUser: Bool { message.role == .user }

    /// Strip the noisy "Reference(s): [Source 1] …" trailing block some
    /// models still emit even with the updated prompt. Anything from the
    /// first standalone "Reference" / "References" line to end-of-message
    /// is dropped before rendering.
    private var cleanedContent: String {
        guard !isUser else { return message.content }
        var text = message.content
        let patterns = [
            "\n\nReferences?:",
            "\nReferences?:",
            "\n\nReference\\(s\\):",
            "\nReference\\(s\\):",
        ]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return text
    }

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: Japandi.Spacing.xxl) }

            if isUser {
                // User turn — keep the bubble so the question is visually
                // anchored opposite the assistant's open prose.
                userBubble
            } else {
                // Assistant turn — render as a flat, breathable column. No
                // surrounding card, no inset; the page is the surface, just
                // like NotebookLM. Spacing is what carries hierarchy.
                assistantColumn
            }

            if !isUser { Spacer(minLength: Japandi.Spacing.xxl) }
        }
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(message.content)
                .font(Japandi.Typography.body)
                .foregroundStyle(.white)
                .textSelection(.enabled)
            Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .padding(.horizontal, Japandi.Spacing.md)
        .padding(.vertical, Japandi.Spacing.sm)
        .background(Japandi.Colors.inkSolidFallback)
        .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Japandi.Radius.md, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .japandiShadow(Japandi.Shadow.subtle)
    }

    private var assistantColumn: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.xs) {
            if sources.isEmpty {
                // No retrieved context — still render block-aware, just
                // without citation pills (RichMessage degrades cleanly).
                RichMessage(text: cleanedContent, sources: [])
            } else {
                RichMessage(text: cleanedContent, sources: sources)
            }
            Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9))
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                .padding(.top, 2)
        }
        .padding(.horizontal, Japandi.Spacing.md)
        .padding(.vertical, Japandi.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Source Card

// NotebookLM-style source card. Numbered chip on the left, document title +
// page in serif, snippet underneath, hover state with accent rim. Click opens
// the document in the library via the `.selectDocumentByID` notification.
struct SourceCard: View {
    let source: RAGSource
    var index: Int? = nil

    @State private var isHovered = false

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: .selectDocumentByID,
                object: nil,
                userInfo: ["documentID": source.documentID]
            )
        } label: {
            HStack(alignment: .top, spacing: Japandi.Spacing.sm) {
                // Numbered chip — anchor for "[Source 3]" style citations.
                Text(index.map { "\($0)" } ?? "·")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(isHovered
                                     ? Japandi.Colors.accentFallback
                                     : Japandi.Colors.accentMutedFallback)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(isHovered
                                  ? Japandi.Colors.washFallback
                                  : Japandi.Colors.surfaceFallback)
                            .overlay(
                                Circle().strokeBorder(
                                    isHovered
                                        ? Japandi.Colors.accentFallback.opacity(0.45)
                                        : Japandi.Colors.borderFallback,
                                    lineWidth: 0.5
                                )
                            )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    // Title row — primary affordance, scales with serif weight.
                    HStack(spacing: 4) {
                        Text(source.documentTitle ?? "Untitled document")
                            .font(.system(size: 12.5, weight: .medium, design: .serif))
                            .foregroundStyle(Japandi.Colors.textPrimaryFB)
                            .lineLimit(1)
                        if let page = source.pageNumber {
                            Text("· p.\(page)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                        }
                        Spacer(minLength: 4)
                        Text("\(source.relevancePercent)%")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Japandi.Colors.accentFallback)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(isHovered
                                             ? Japandi.Colors.accentFallback
                                             : Japandi.Colors.textTertiaryFB)
                    }
                    Text(source.chunkText)
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textSecondaryFB)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, Japandi.Spacing.sm)
            .padding(.vertical, 8)
            .background(isHovered
                        ? Japandi.Colors.washFallback.opacity(0.6)
                        : Japandi.Colors.surfaceRaisedFB)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isHovered
                            ? Japandi.Colors.accentFallback.opacity(0.45)
                            : Japandi.Colors.borderFallback.opacity(0.85),
                        lineWidth: isHovered ? 0.75 : 0.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open \(source.documentTitle ?? "document") in the library")
        .accessibilityLabel("Open source \(index.map { "\($0)" } ?? "") · \(source.documentTitle ?? "")")
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
