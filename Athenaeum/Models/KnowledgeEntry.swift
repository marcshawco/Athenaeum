import Foundation
import SwiftData

// MARK: - Knowledge Entry (Word Bank)
//
// User-curated glossary entries that teach the local AI which terms refer to
// the same real-world entity. A single entry binds:
//   - one *canonical name* the AI should use ("Marcus Shaw")
//   - any number of *aliases* the user might type or that appear in docs
//     ("me", "I", "Marc", "Marcus")
//   - a free-form *notes* field that becomes part of the system prompt
//     ("my medical insurance provider")
//   - a *category* (Person, Organization, Medical, Education, etc.) used
//     for grouping in the UI
//   - an *isSelf* flag for the special "this entry IS the user" entry — the
//     AI is told to interpret first-person pronouns as referring to it.

@Model
final class KnowledgeEntry {
    @Attribute(.unique) var id: UUID

    /// Display + canonical name. AI is asked to use this form when
    /// referring to the entity. Required, non-empty.
    var canonicalName: String

    /// Other strings that should be treated as the same entity. Lowercased
    /// on save so query expansion can do a simple set membership check.
    var aliases: [String]

    /// Free-form text the AI sees: "my medical insurance provider",
    /// "online university where I'm studying cybersecurity", etc.
    var notes: String?

    /// One of `KnowledgeCategory.allCases.rawValue` or nil for uncategorized.
    var category: String?

    /// When true, the AI is told "the user IS this entity". Only one entry
    /// can be the self entry at a time — `KnowledgeBaseService` enforces
    /// the invariant by clearing the flag on others when this is set.
    var isSelf: Bool

    var createdAt: Date
    var modifiedAt: Date

    init(
        canonicalName: String,
        aliases: [String] = [],
        notes: String? = nil,
        category: String? = nil,
        isSelf: Bool = false
    ) {
        self.id = UUID()
        self.canonicalName = canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.aliases = KnowledgeEntry.normalizeAliases(aliases)
        self.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.category = category
        self.isSelf = isSelf
        self.createdAt = .now
        self.modifiedAt = .now
    }

    /// Lowercased, deduplicated, non-empty alias list. Stored this way so
    /// downstream lookups don't have to renormalize on every retrieval.
    static func normalizeAliases(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for a in raw {
            let trimmed = a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }

    /// All distinct surface forms — canonical + aliases — used by the
    /// title-match boost. Lowercased for fast comparison.
    var surfaceForms: [String] {
        var forms = aliases
        forms.append(canonicalName.lowercased())
        return Array(Set(forms))
    }
}

// MARK: - Categories

enum KnowledgeCategory: String, CaseIterable, Identifiable, Sendable {
    case person       = "Person"
    case organization = "Organization"
    case medical      = "Medical / Healthcare"
    case financial    = "Financial / Insurance"
    case education    = "Education"
    case housing      = "Housing / Real Estate"
    case employer     = "Employer / Client"
    case legal        = "Legal"
    case place        = "Place"
    case other        = "Other"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .person:       "person.crop.circle"
        case .organization: "building.2"
        case .medical:      "cross.case"
        case .financial:    "banknote"
        case .education:    "graduationcap"
        case .housing:      "house"
        case .employer:     "briefcase"
        case .legal:        "scalemass"
        case .place:        "mappin.and.ellipse"
        case .other:        "tag"
        }
    }
}

// MARK: - Helpers

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
