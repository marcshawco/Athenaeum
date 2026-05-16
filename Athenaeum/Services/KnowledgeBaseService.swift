import Foundation
import SwiftData

// MARK: - Knowledge Base Service
//
// Plumbing between the user's `KnowledgeEntry` rows and the RAG / chat
// pipeline. Three things it does for the local AI:
//   1. Query expansion — rewrite the user's question so retrieval can match
//      documents that use the *canonical* form when the user typed an alias
//      (or a first-person pronoun).
//   2. Title-match alias set — every surface form (canonical + aliases) is
//      added to the title-match boost pool so retrieval favours docs whose
//      titles mention any known form of the entity.
//   3. System-prompt context — short, dense block injected at the top of
//      the chat system prompt teaching the model who "I" is and what each
//      entity actually is.
//
// The service is built once and lives on the SwiftData ModelContext. It
// re-reads on every call so edits in the UI take effect on the next chat
// turn without any cache-invalidation dance.

@MainActor
final class KnowledgeBaseService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Snapshot

    /// Fetch every entry, sorted by canonical name for stable iteration.
    /// Empty list on failure — this service is best-effort; the rest of
    /// RAG still works without a word bank.
    @MainActor
    func entries() -> [KnowledgeEntry] {
        let descriptor = FetchDescriptor<KnowledgeEntry>(
            sortBy: [SortDescriptor(\.canonicalName)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    var selfEntry: KnowledgeEntry? {
        entries().first(where: { $0.isSelf })
    }

    // MARK: - Query expansion

    /// Tokenize a question and, for any token (or first-person pronoun)
    /// that matches an entry's alias, append the entry's canonical name to
    /// the query. So "what's on my resume?" with a self-entry "Marcus Shaw"
    /// becomes "what's on my resume? Marcus Shaw" before embedding, which
    /// makes vector retrieval find the right doc even when its title is
    /// the only place "Marcus Shaw" appears.
    @MainActor
    func expandedQuery(for question: String) -> String {
        let snapshot = entries()
        guard !snapshot.isEmpty else { return question }

        let lowerQuery = question.lowercased()
        var injected: [String] = []
        var seen = Set<String>()

        // First-person pronoun handling — only when a self-entry exists.
        if let me = snapshot.first(where: { $0.isSelf }) {
            let pronouns = ["me", "i", "my", "myself", "mine", "i'm", "i've", "i'll", "i'd"]
            for token in tokenize(lowerQuery) where pronouns.contains(token) {
                if seen.insert(me.canonicalName.lowercased()).inserted {
                    injected.append(me.canonicalName)
                }
                break
            }
        }

        // Alias hits — scan every entry's surface forms against the query
        // substring (so multi-word aliases like "my school" still match).
        for entry in snapshot {
            for form in entry.surfaceForms where !form.isEmpty {
                // Use word-boundary-ish containment: surround with spaces so
                // "kaiser" matches " kaiser " but not "kaisertown".
                let padded = " \(lowerQuery) "
                if padded.contains(" \(form) ") || padded.contains(" \(form),") || padded.contains(" \(form).") {
                    if seen.insert(entry.canonicalName.lowercased()).inserted {
                        injected.append(entry.canonicalName)
                    }
                    break
                }
            }
        }

        guard !injected.isEmpty else { return question }
        return "\(question) [\(injected.joined(separator: ", "))]"
    }

    /// Returns every surface form (canonical + aliases) across the whole
    /// word bank. Used to extend the title-match boost set so a doc titled
    /// "Kaiser EOB September" gets boosted on questions that mentioned
    /// any alias mapped to that entity.
    @MainActor
    func allSurfaceForms() -> Set<String> {
        Set(entries().flatMap { $0.surfaceForms })
    }

    /// Expand a query's token set with canonical names for every alias the
    /// query matches. Returns a *bag of tokens* the retrieval boost can
    /// intersect with document titles. Lets us boost a Kaiser doc on the
    /// question "any medical bills this month?" via the `medical` notes
    /// associated with the Kaiser entry — handled by injecting `kaiser`
    /// into the boost token set.
    @MainActor
    func expandedBoostTokens(for question: String) -> Set<String> {
        let snapshot = entries()
        guard !snapshot.isEmpty else { return [] }

        let lowered = " \(question.lowercased()) "
        var tokens = Set<String>()

        for entry in snapshot {
            // If the query mentions this entity (via any surface form or
            // a category match like "medical"), enrol every canonical-name
            // token plus every alias token into the boost set so docs that
            // reference any form of the entity get a bump.
            let categoryHit = entry.category.map { lowered.contains(" \($0.lowercased()) ") } ?? false
            let formHit = entry.surfaceForms.contains { form in
                lowered.contains(" \(form) ") || lowered.contains(" \(form),") || lowered.contains(" \(form).")
            }
            let categoryAliasHit = categoryAliasMatch(lowered: lowered, entry: entry)
            guard formHit || categoryHit || categoryAliasHit else { continue }

            tokens.formUnion(splitTokens(entry.canonicalName))
            for alias in entry.aliases {
                tokens.formUnion(splitTokens(alias))
            }
        }
        return tokens
    }

    /// Some category words have natural-language synonyms users actually
    /// say. "Medical" should also fire on "doctor", "appointment",
    /// "prescription", "hospital", etc. Keep it small — we're only nudging
    /// retrieval, not building a thesaurus.
    private func categoryAliasMatch(lowered: String, entry: KnowledgeEntry) -> Bool {
        guard let raw = entry.category, let cat = KnowledgeCategory(rawValue: raw) else { return false }
        let synonyms: [String]
        switch cat {
        case .medical:    synonyms = ["doctor", "appointment", "prescription", "hospital", "clinic", "health", "rx"]
        case .financial:  synonyms = ["bank", "loan", "insurance", "premium", "claim", "policy", "statement"]
        case .education:  synonyms = ["school", "course", "tuition", "transcript", "grade", "degree", "class"]
        case .housing:    synonyms = ["lease", "rent", "landlord", "tenant", "apartment", "deed", "mortgage"]
        case .employer:   synonyms = ["work", "job", "salary", "paystub", "offer", "termination"]
        case .legal:      synonyms = ["contract", "agreement", "lawyer", "attorney", "court", "filing"]
        case .person, .organization, .place, .other:
            return false
        }
        for s in synonyms where lowered.contains(" \(s) ") {
            return true
        }
        return false
    }

    // MARK: - System-prompt context

    /// Compact block of text appended to the chat system prompt. Teaches
    /// the model who "I" is and what every known entity actually is.
    /// Skipped entirely when the word bank is empty so we don't burn
    /// tokens on a no-op preamble.
    @MainActor
    func systemPromptContext() -> String {
        let all = entries()
        guard !all.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("USER CONTEXT — facts the user has told you, treat as ground truth:")

        if let me = all.first(where: { $0.isSelf }) {
            var bits = ["The user is \(me.canonicalName)"]
            if !me.aliases.isEmpty {
                bits.append("also known as \(me.aliases.joined(separator: ", "))")
            }
            if let notes = me.notes, !notes.isEmpty { bits.append(notes) }
            lines.append("- " + bits.joined(separator: "; ") + ". When they say \"I\", \"me\", or \"my\", they mean \(me.canonicalName).")
        }

        for entry in all where !entry.isSelf {
            var parts = [entry.canonicalName]
            if !entry.aliases.isEmpty {
                parts.append("(aka \(entry.aliases.joined(separator: ", ")))")
            }
            if let cat = entry.category, !cat.isEmpty {
                parts.append("— \(cat)")
            }
            if let notes = entry.notes, !notes.isEmpty {
                parts.append(": \(notes)")
            }
            lines.append("- " + parts.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func splitTokens(_ phrase: String) -> [String] {
        phrase.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    // MARK: - Mutations

    /// Save a new or edited entry. When `isSelf` is true on the saved row,
    /// clears the flag on every other row so "I am" can only point at one
    /// person at a time.
    @MainActor
    func upsert(_ entry: KnowledgeEntry, isNew: Bool) {
        if entry.isSelf {
            for other in entries() where other.id != entry.id && other.isSelf {
                other.isSelf = false
            }
        }
        entry.modifiedAt = .now
        if isNew { context.insert(entry) }
        try? context.save()
    }

    @MainActor
    func delete(_ entry: KnowledgeEntry) {
        context.delete(entry)
        try? context.save()
    }
}
