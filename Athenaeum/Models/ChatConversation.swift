import Foundation
import SwiftData

// MARK: - Chat Conversation
//
// SwiftData-backed persistence for a single chat thread. Messages are JSON-
// encoded onto the conversation rather than modelled as their own entity —
// keeps the schema flat, makes "duplicate this chat" a single field copy,
// and dodges the SwiftData reverse-relationship dance for what is really
// just an ordered list of immutable strings.

@Model
final class ChatConversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date

    /// JSON-encoded `[StoredMessage]`. Empty string means an unused / fresh
    /// conversation. We keep the on-disk shape stable by versioning via a
    /// container envelope (`StoredMessageEnvelope`) so future fields can be
    /// added without losing old chats.
    @Attribute(.externalStorage)
    var messagesJSON: String

    init(title: String = "New chat") {
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.modifiedAt = .now
        self.messagesJSON = ""
    }
}

// MARK: - On-disk message shape

/// Mirror of the in-memory `ChatMessage` struct that lives in `LLMService`,
/// without the Sendable / Identifiable concerns of the runtime type. Encoded
/// to JSON inside `ChatConversation.messagesJSON`.
struct StoredMessage: Codable, Hashable {
    var id: UUID
    var role: String          // "system" | "user" | "assistant"
    var content: String
    var timestamp: Date
    /// Sources captured for this assistant turn. Empty for user/system rows.
    var sources: [StoredSource]

    init(from message: ChatMessage, sources: [RAGSource] = []) {
        self.id = message.id
        self.role = message.role.rawValue
        self.content = message.content
        self.timestamp = message.timestamp
        self.sources = sources.map { StoredSource(from: $0) }
    }

    var chatMessage: ChatMessage {
        // Best-effort rehydration; unknown roles collapse to .assistant so
        // they still render rather than disappearing on a future schema bump.
        let parsedRole = ChatRole(rawValue: role) ?? .assistant
        return ChatMessage(id: id, role: parsedRole, content: content, timestamp: timestamp)
    }

    var ragSources: [RAGSource] {
        sources.map { $0.ragSource }
    }
}

struct StoredSource: Codable, Hashable {
    var documentID: UUID
    var documentTitle: String?
    var chunkText: String
    var relevance: Float
    var pageNumber: Int?

    init(from source: RAGSource) {
        self.documentID = source.documentID
        self.documentTitle = source.documentTitle
        self.chunkText = source.chunkText
        self.relevance = source.relevance
        self.pageNumber = source.pageNumber
    }

    var ragSource: RAGSource {
        RAGSource(
            documentID: documentID,
            documentTitle: documentTitle,
            chunkText: chunkText,
            relevance: relevance,
            pageNumber: pageNumber
        )
    }
}

/// Versioned envelope written to disk. v1 is the only version today but the
/// envelope lets us migrate without writing a SwiftData migration.
struct StoredMessageEnvelope: Codable {
    var version: Int
    var messages: [StoredMessage]
}

// MARK: - Codec helpers

extension ChatConversation {
    /// Decoded message list. Returns an empty array on first load or on
    /// JSON-decode failure (better than crashing on a schema drift).
    func storedMessages() -> [StoredMessage] {
        guard !messagesJSON.isEmpty,
              let data = messagesJSON.data(using: .utf8) else { return [] }
        if let envelope = try? JSONDecoder().decode(StoredMessageEnvelope.self, from: data) {
            return envelope.messages
        }
        // Older builds wrote a bare array — keep that compatible.
        if let bare = try? JSONDecoder().decode([StoredMessage].self, from: data) {
            return bare
        }
        return []
    }

    /// Replace the persisted messages with `newValue`. Updates `modifiedAt`
    /// so the chat list can sort by recency.
    func setStoredMessages(_ newValue: [StoredMessage]) {
        let envelope = StoredMessageEnvelope(version: 1, messages: newValue)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(envelope),
           let json = String(data: data, encoding: .utf8) {
            self.messagesJSON = json
            self.modifiedAt = .now
        }
    }

    /// Convenience for the chat history popover — the first user message,
    /// trimmed to a previewable length.
    var preview: String {
        let msgs = storedMessages()
        if let firstUser = msgs.first(where: { $0.role == "user" }) {
            return firstUser.content
        }
        if let first = msgs.first {
            return first.content
        }
        return "Empty"
    }
}
