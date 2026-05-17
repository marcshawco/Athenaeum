import Foundation
import SwiftData

@Model
final class Tag {
    @Attribute(.unique) var name: String
    var colorHex: String
    var createdAt: Date
    var documents: [Document]?

    init(name: String, colorHex: String = "2A639D", createdAt: Date = .now) {
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

// MARK: - Predefined Tag Categories

extension Tag {
    static let defaultColors: [String] = [
        "2A639D",
        "6191CF",
        "9CD7FF",
        "003A6E",
        "C7F3FF",
    ]

    /// Broad domain anchors for document classification.
    ///
    /// History note: this pool used to be ~1,100 narrow slugs across every
    /// niche subdomain we could think of (every medical specialty, every
    /// crypto coin, every programming language). It was load-bearing — the
    /// tagger validator strictly rejected anything outside this list, so
    /// missing a domain meant documents in that domain came back tagged
    /// only "to-review".
    ///
    /// As of v2.5.0 the validator in `DocumentProcessor.ensureUsefulTags`
    /// is permissive: anything in this pool OR any well-formed slug the
    /// model invents (lowercase alphanumeric with hyphens, 2–40 chars,
    /// no leading/trailing/doubled hyphens) is accepted. That means the
    /// pool's job is no longer "all valid tags" — it's "anchor terminology
    /// the model should prefer." When the user files a fitness PDF, we
    /// want the model to pick `fitness` rather than `workouts-and-stuff`,
    /// so we anchor `fitness`. The model then composes specific tags from
    /// the anchor (`fitness-plan`, `fitness-progress`) that pass through.
    ///
    /// One or two anchors per real-world filing domain is plenty. Don't
    /// fall into the trap of adding `tennis`, `basketball`, `soccer` —
    /// `sports` is the anchor; the model will compose the rest. Same for
    /// every other "300 slugs per sector" temptation.
    static let builtInPool: [String] = [
        // Identity & legal
        "identity", "legal", "contract", "court", "estate", "license", "permit",
        // Health & medical
        "health", "medical", "mental-health", "prescription", "veterinary",
        // Financial
        "financial", "banking", "credit", "loan", "mortgage", "investment",
        "retirement", "tax", "receipt", "invoice", "payment", "budget", "statement",
        // Employment & HR & career
        "employment", "resume", "payroll", "contractor", "career",
        // Education / learning
        "education", "school", "course", "tutorial", "certification", "transcript",
        // Real estate & property
        "real-estate", "property", "lease", "deed", "hoa", "home-improvement",
        // Insurance
        "insurance", "policy", "claim", "warranty",
        // Vehicle
        "vehicle", "registration",
        // Utilities & subscriptions
        "utilities", "subscription", "membership",
        // Correspondence
        "correspondence", "letter", "email", "notice",
        // Business / marketing / social
        "business", "entrepreneurship", "marketing", "branding", "sales",
        "social-media", "client", "vendor",
        // Project / meetings / notes
        "project", "meeting-notes", "notes", "report", "presentation", "spreadsheet", "roadmap",
        // Operations / logistics
        "operations", "shipping", "inventory", "procurement", "manufacturing",
        // Retail / hospitality / fashion / food
        "retail", "hospitality", "restaurant", "fashion",
        "food", "recipe", "cooking", "nutrition",
        // Fitness / wellness
        "fitness", "wellness", "workout",
        // Security / compliance
        "security", "compliance", "audit", "privacy", "safety",
        // Forms / templates
        "form", "template", "manual", "guide", "checklist",
        // Research / writing
        "research", "article", "whitepaper", "essay", "writing",
        // Software / engineering / cloud
        "software", "engineering", "code", "api", "design", "ui", "ux", "devops", "cloud", "ai",
        // Travel
        "travel", "itinerary", "flight", "hotel", "reservation", "vacation",
        // Events / life moments
        "event", "conference", "wedding", "birthday", "graduation", "funeral", "anniversary",
        // Home / family
        "home", "household", "family", "parenting", "childcare",
        // Government / civic
        "government", "election", "military", "veteran",
        // Sports / recreation
        "sports", "hiking", "camping", "fishing", "gaming",
        // Arts / creative / video
        "art", "photography", "music", "film", "video", "graphic-design", "podcast",
        // Books / reading
        "book",
        // News / journalism
        "news", "press-release",
        // Science
        "science", "math",
        // Construction / trades / DIY
        "construction", "diy", "plumbing", "electrical", "landscape",
        // Energy / sustainability
        "solar", "renewable", "sustainability",
        // Beauty / personal care
        "beauty", "skincare",
        // Pets / animals
        "pet", "dog", "cat",
        // Productivity / personal development / mindset
        "productivity", "todo", "journal", "meditation", "habit", "mindset",
        // Religious / spiritual / philosophy
        "spiritual", "religious", "philosophy",
        // Languages / translation
        "translation", "localization",
        // Home goods / shopping
        "furniture", "appliance", "electronics", "smart-home",
        // Crypto / fintech
        "crypto", "blockchain", "nft",
        // Status flags (used by UI filters as well as tagging)
        "urgent", "to-review", "follow-up", "paid", "unpaid", "overdue",
        "pending", "approved", "confidential", "draft", "final", "archived",
        "in-progress", "blocked", "done", "needs-signature", "expired", "active",
    ]
}
