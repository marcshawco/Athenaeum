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

    /// Built-in vocabulary for document classification. These tags are used as
    /// a pool for AI/fallback tagging and are only created in the library when
    /// a document actually receives them.
    static let builtInPool: [String] = [
        // Identity & legal
        "identity", "passport", "drivers-license", "social-security", "birth-certificate", "marriage-certificate", "divorce", "adoption",
        "citizenship", "visa", "immigration", "address", "contact", "emergency-contact", "beneficiary", "estate",
        "will", "trust", "power-of-attorney", "notary", "legal", "court", "attorney", "claim",
        "settlement", "affidavit", "subpoena", "judgment", "permit", "license",
        // Medical
        "medical", "dental", "vision", "prescription", "pharmacy", "lab-results", "imaging", "vaccination",
        "insurance-card", "benefits", "explanation-of-benefits", "diagnosis", "treatment", "referral",
        "provider", "patient", "health-record", "therapy", "mental-health", "veterinary", "pet",
        // Financial
        "bank-statement", "checking", "savings", "credit-card", "debit-card", "transaction", "deposit",
        "withdrawal", "transfer", "loan", "mortgage", "refinance", "interest", "investment", "brokerage",
        "retirement", "ira", "401k", "pension", "dividend", "statement", "budget", "expense", "receipt",
        "invoice", "bill", "payment", "refund", "reimbursement",
        // Tax
        "tax", "w-2", "1099", "1040", "schedule-c", "deduction", "charitable-donation", "property-tax",
        "sales-tax", "payroll-tax", "estimated-tax", "tax-return", "tax-notice", "irs",
        // Accounting / business operations
        "bookkeeping", "accounting", "ledger", "balance-sheet", "profit-loss", "cash-flow",
        "accounts-payable", "accounts-receivable", "payroll", "paystub", "timesheet",
        // Employment & HR
        "contractor", "employee", "offer-letter", "onboarding", "handbook", "performance-review", "termination",
        "resume", "cv", "cover-letter", "reference-check", "background-check", "job-description",
        "compensation", "equity-grant", "stock-options", "severance", "non-compete", "career",
        // Education
        "training", "certification", "transcript", "diploma", "tuition", "scholarship", "financial-aid",
        "student-loan", "school", "education", "course", "credit", "credit-transfer", "curriculum",
        "academic", "university", "college", "syllabus", "prerequisite", "articulation", "enrollment",
        "registration-form", "academic-record", "degree-plan",
        // Contracts
        "contract", "agreement", "nda", "statement-of-work", "proposal", "quote", "estimate", "purchase-order",
        "work-order", "change-order", "scope", "deliverables", "milestone", "invoice-terms", "signature",
        "signed", "renewal", "amendment", "addendum", "termination-clause",
        // Real estate & property
        "lease", "rent", "tenant", "landlord", "property", "real-estate", "deed", "title", "appraisal", "inspection",
        // Insurance
        "insurance", "auto-insurance", "home-insurance", "renters-insurance", "life-insurance",
        "business-insurance", "policy", "premium", "deductible", "coverage", "accident", "repair",
        "warranty", "service-record", "maintenance",
        // Vehicle
        "vehicle", "registration", "vin", "title-transfer", "parking", "toll", "ticket",
        // Utilities & subscriptions
        "utilities", "electric", "gas", "water", "internet", "phone", "mobile", "subscription",
        "membership", "cancellation", "account", "login", "password", "confirmation", "receipt-email",
        // Correspondence
        "correspondence", "letter", "email", "memo", "notice", "reminder", "invitation", "announcement", "newsletter",
        // Business / marketing
        "application", "business-plan", "marketing", "advertising", "brand", "branding", "brand-strategy",
        "marketing-strategy", "content-strategy", "pr", "campaign", "creative-brief", "pitch-deck",
        "case-study", "sales", "client", "customer", "lead", "vendor", "supplier", "partner",
        // Project / meetings
        "project", "meeting-notes", "agenda", "minutes", "report", "presentation", "spreadsheet",
        "dashboard", "analytics", "kpi", "okr", "roadmap",
        // Operations / logistics
        "inventory", "shipping", "delivery", "packing-slip", "bill-of-lading", "order", "fulfillment",
        "return", "rma", "procurement", "manufacturing", "operations",
        // Retail / hospitality / service industry / fashion
        "retail", "merchandising", "store-operations", "point-of-sale", "ecommerce",
        "hospitality", "hotel-operations", "front-desk", "concierge", "housekeeping",
        "restaurant", "food-service", "menu", "kitchen-operations",
        "fashion", "apparel", "luxury", "streetwear", "footwear", "accessories",
        // Food / cooking / nutrition / wellness / fitness
        "recipe", "ingredients", "cooking", "baking", "meal-plan", "meal-prep",
        "dessert", "entree", "appetizer", "beverage", "snack", "dietary-restrictions",
        "nutrition", "protein", "supplement", "calories", "macros",
        "health", "wellness", "fitness", "workout", "exercise", "diet", "weight-loss",
        // Security / safety
        "compliance", "procedure", "standard-operating-procedure", "audit", "safety", "incident",
        "security", "loss-prevention", "asset-protection", "investigation", "surveillance",
        "access-control", "privacy", "data", "gdpr", "hipaa", "accessibility", "risk", "assessment", "checklist",
        // Forms / templates
        "form", "template", "manual", "guide", "instructions", "specification", "requirements",
        // Research / writing
        "research", "article", "whitepaper", "essay", "analysis", "thesis", "literature-review",
        // Software / engineering / design
        "software", "engineering", "code", "documentation", "api", "architecture", "release-notes",
        "bug-report", "feature-spec", "design", "ux", "ui", "wireframe", "prototype", "style-guide",
        // Travel
        "travel", "itinerary", "boarding-pass", "flight", "hotel", "reservation", "rental-car",
        "passport-copy", "visa-copy",
        // Events
        "event", "conference", "workshop", "mileage", "per-diem",
        // Home / family
        "home", "household", "moving", "storage", "renovation", "contractor-bid", "blueprint", "floor-plan",
        "hoa", "mortgage-statement", "escrow", "utilities-bill", "family", "childcare", "daycare", "eldercare", "consent-form",
        // Parenting & school
        "parenting", "babysitter", "nanny", "school-form", "permission-slip", "field-trip", "parent-teacher-conference",
        "report-card", "well-child-visit", "growth-chart", "milestone", "baby", "infant", "toddler", "teenager",
        "allowance", "chore-chart", "preschool", "kindergarten", "elementary-school", "middle-school", "high-school",
        "college-application", "fafsa", "scholarship-application", "school-supplies",
        // Medical specialties & care types
        "cardiology", "neurology", "oncology", "dermatology", "pediatrics", "geriatrics", "psychiatry", "psychology",
        "orthopedics", "urology", "gastroenterology", "endocrinology", "ophthalmology", "ent", "podiatry",
        "obgyn", "fertility", "pregnancy", "prenatal", "postpartum", "ultrasound", "birth-plan", "newborn",
        "surgery", "surgical-consent", "pre-op", "post-op", "anesthesia", "recovery-plan",
        "physical-therapy", "occupational-therapy", "speech-therapy", "rehabilitation",
        "emergency-room", "urgent-care", "primary-care", "telehealth", "specialist-visit", "second-opinion",
        "medication-list", "prescription-refill", "side-effects", "drug-interaction",
        "counseling", "therapy-session", "anxiety", "depression", "stress-management", "sleep-study",
        "hearing-test", "eye-exam", "blood-test", "biopsy", "mri", "x-ray", "ct-scan", "mammogram", "colonoscopy",
        "advance-directive", "living-will", "do-not-resuscitate",
        // Personal finance deep
        "emergency-fund", "savings-goal", "investment-portfolio", "asset-allocation", "diversification",
        "etf", "mutual-fund", "index-fund", "stock", "bond", "options-trading", "futures",
        "dividend-reinvestment", "capital-gains", "tax-loss-harvesting", "roth-conversion",
        "529-plan", "hsa", "fsa", "hra", "deferred-compensation",
        "credit-score", "credit-report", "fico", "debt-management", "debt-consolidation",
        "balance-transfer", "credit-utilization", "hard-inquiry", "soft-inquiry",
        "net-worth", "financial-plan", "retirement-projection", "social-security-statement",
        "estate-plan", "inheritance", "probate", "executor", "guardianship",
        "annuity", "whole-life", "term-life", "umbrella-policy",
        // Crypto / fintech
        "crypto", "bitcoin", "ethereum", "stablecoin", "altcoin", "nft", "defi",
        "blockchain", "smart-contract", "wallet-address", "seed-phrase", "private-key", "public-key",
        "hardware-wallet", "exchange-statement", "crypto-tax", "yield-farming", "staking", "mining",
        // Government & civic
        "government", "federal", "state", "local", "municipal", "county",
        "election", "voting", "ballot", "voter-registration", "polling-place",
        "campaign", "candidate", "debate", "primary-election", "general-election",
        "building-permit", "zoning", "code-enforcement", "occupancy-permit", "certificate-of-occupancy",
        "jury-duty", "warrant", "citation", "fine", "summons",
        "legislation", "statute", "regulation", "ordinance",
        "military", "veteran", "va-benefits", "dd-214", "deployment-orders", "discharge-papers",
        "social-services", "snap", "wic", "tanf", "unemployment-benefits", "disability-claim",
        "census", "tax-id", "ein",
        // Sports, recreation, outdoor
        "sports", "athletics", "baseball", "basketball", "football", "soccer", "hockey", "tennis",
        "golf", "swimming", "running", "cycling", "triathlon", "marathon", "5k",
        "yoga", "pilates", "martial-arts", "boxing", "wrestling", "climbing", "bouldering",
        "skating", "skiing", "snowboarding", "surfing", "sailing", "fishing", "hunting",
        "camping", "hiking", "backpacking", "trail-run", "kayaking", "canoeing",
        "team", "league", "tournament", "championship", "playoff", "season-pass",
        "roster", "stats", "scorecard", "scouting-report", "training-camp",
        "gym-membership", "personal-trainer", "trainer-session", "fitness-plan",
        // Arts & creative
        "art", "artwork", "painting", "sculpture", "drawing", "illustration", "sketch", "portfolio",
        "gallery", "museum", "exhibition", "art-history", "art-criticism", "art-supplies",
        "photography", "photo", "photographer", "photo-shoot", "photo-album", "raw-file",
        "lens", "camera", "lightroom", "photoshop",
        "music", "song", "album", "playlist", "concert", "lyrics", "sheet-music",
        "music-theory", "instrument", "guitar", "piano", "drums", "vocals",
        "recording", "mixing", "mastering", "songwriting", "composition", "arrangement",
        "musician", "band", "orchestra", "choir",
        "film", "video", "screenplay", "script", "storyboard", "treatment",
        "cinematography", "editing", "post-production", "vfx", "color-grade", "sound-design",
        "voice-over", "podcast", "livestream", "vlog", "youtube-channel", "tiktok",
        "writing", "novel", "short-story", "poetry", "memoir", "blog", "manuscript", "draft",
        "literary-agent", "publishing", "isbn", "copyright", "trademark",
        "graphic-design", "typography", "logo-design", "color-palette", "mood-board", "packaging-design",
        // Books / publishing / reading
        "book", "non-fiction", "fiction", "biography", "autobiography", "self-help-book",
        "audiobook", "ebook", "kindle", "library-book", "book-club", "reading-list", "book-review",
        "chapter", "foreword", "preface", "afterword", "index", "glossary", "bibliography",
        "self-published", "manuscript-submission",
        // News / journalism / politics
        "news", "news-article", "op-ed", "editorial", "press-release", "news-clipping",
        "interview", "press-kit", "politics", "advocacy", "petition", "lobbying",
        // Science & technical
        "science", "biology", "chemistry", "physics", "astronomy", "geology", "meteorology",
        "experiment", "lab-notebook", "data-analysis", "hypothesis", "methodology", "peer-review",
        "math", "statistics", "geometry", "algebra", "calculus", "equation", "formula",
        "engineering-disc", "mechanical", "electrical", "civil", "chemical", "aerospace",
        "patent", "prior-art", "invention", "prototype-spec",
        // Software / programming / cloud / DevOps / AI
        "programming", "python", "javascript", "typescript", "swift", "java", "rust", "go-lang",
        "kotlin", "cpp", "csharp", "ruby", "php", "sql", "html", "css", "shell-script",
        "framework", "library", "package", "dependency", "semver", "changelog",
        "database", "postgres", "mysql", "mongodb", "redis", "sqlite",
        "cloud", "aws", "azure", "gcp", "kubernetes", "docker", "container", "microservice",
        "devops", "ci-cd", "github-actions", "deployment", "rollback",
        "monitoring", "alerting", "observability", "logging",
        "pen-test", "vulnerability", "cve", "sast", "dast", "incident-response",
        "ai", "machine-learning", "deep-learning", "neural-network", "llm", "fine-tune",
        "training-data", "embedding", "model-card", "evaluation",
        "mobile-dev", "ios-dev", "android-dev", "react-native", "flutter", "swiftui",
        "frontend", "backend", "fullstack", "rest-api", "graphql", "webhook", "websocket",
        // Construction / trades / DIY
        "construction", "general-contractor", "subcontractor", "plumber", "electrician", "carpenter",
        "painter", "roofer", "hvac-tech", "mason", "tiler", "drywaller",
        "bid", "punch-list", "draw-schedule", "lien-waiver", "material-receipt",
        "lumber", "drywall", "concrete", "paint-spec", "fixtures",
        "diy", "home-improvement", "remodel", "addition", "extension",
        "landscape", "garden", "lawn-care", "irrigation", "fence-install", "deck",
        // Energy & sustainability
        "solar", "solar-panel", "solar-permit", "energy-audit", "energy-efficiency", "weatherization",
        "electric-vehicle", "ev-charging", "charging-station",
        "recycling", "composting", "sustainability", "eco-friendly", "carbon-footprint",
        "renewable", "wind", "hydro", "geothermal", "net-metering",
        // Vehicle deep
        "car", "truck", "suv", "motorcycle", "rv", "boat", "trailer",
        "car-loan-statement", "car-payment", "oil-change", "tire-rotation", "brake-service", "tune-up",
        "gas-receipt", "ev-charging-receipt", "smog-check", "emissions",
        "accident-report", "police-report", "traffic-violation", "dui", "moving-violation",
        // Travel deep
        "vacation", "business-trip", "weekend-getaway", "road-trip", "day-trip",
        "cruise", "ferry", "train-ticket", "bus-ticket", "ride-share",
        "airbnb", "vrbo", "hostel", "resort", "all-inclusive",
        "destination", "packing-list", "passport-renewal",
        "currency-exchange", "travel-insurance", "lounge-pass",
        "frequent-flyer", "points", "miles", "loyalty-program", "tsa-precheck", "global-entry",
        // Events & life moments
        "birthday", "anniversary", "wedding", "wedding-invitation", "engagement", "rsvp",
        "funeral", "memorial", "baptism", "graduation", "retirement-party",
        "gift", "gift-card", "thank-you-note", "condolence", "sympathy-card",
        "volunteer", "donation-receipt", "fundraiser", "philanthropy",
        // Beauty / personal care
        "beauty", "skincare", "makeup", "hair-care", "nail-care", "fragrance",
        "spa", "salon", "barber", "manicure", "pedicure", "massage-therapy", "facial",
        "cosmetics", "esthetician",
        // Pets & animals deep
        "dog", "cat", "bird", "fish-pet", "reptile", "exotic-pet",
        "pet-insurance", "pet-license", "microchip", "pet-food", "grooming",
        "pet-training", "pet-daycare", "pet-sitter", "kennel", "boarding",
        "rescue", "shelter", "foster",
        // Gaming / entertainment
        "gaming", "video-game", "board-game", "card-game", "tabletop", "rpg", "mmo",
        "streaming-service", "movie", "tv-show", "episode", "season",
        "console", "pc-gaming", "vr", "augmented-reality",
        // Productivity / organization / personal development
        "todo", "task-list", "kanban", "sprint", "backlog", "retrospective", "standup",
        "one-on-one", "okrs", "kpis", "action-items", "decision-log",
        "filing-system", "archive-box", "inbox-zero", "label-system",
        "self-help", "personal-development", "journal-entry", "gratitude-journal",
        "meditation", "mindfulness", "affirmation", "habit-tracker", "goal-setting",
        // Religious / spiritual
        "spiritual", "prayer-list", "sermon-notes", "scripture", "devotional",
        "bible-study", "religious-record", "church-membership",
        // Languages / writing services
        "translation", "transcription", "captioning", "subtitle",
        "proofreading", "copyediting", "technical-writing", "content-writing", "ghostwriting",
        "localization", "i18n", "style-guide-writing",
        // Home goods / shopping
        "furniture", "appliance", "electronics-product", "home-decor", "lighting-fixture",
        "smart-home", "security-system", "alarm-system",
        "warranty-card", "product-manual", "user-guide", "instructions-product",
        // Mailing / shipping deep
        "tracking-number", "shipping-label", "customs-form", "international-shipping",
        "return-label", "rma-form", "post-office", "po-box",
        // Misc but useful
        "summary-doc", "outline", "draft-doc", "final-draft", "redline", "markup",
        "comparison", "benchmark", "competitive-analysis", "market-research",
        "survey", "questionnaire", "feedback", "testimonial",
        "press-photo", "headshot", "professional-photo",
        // Status flags
        "urgent", "to-review", "follow-up", "paid", "unpaid", "overdue", "pending", "approved", "confidential",
        "draft", "final", "archived", "in-progress", "blocked", "done", "needs-signature", "expired", "active"
    ]
}
