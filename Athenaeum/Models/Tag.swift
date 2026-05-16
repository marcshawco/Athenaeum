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
        "student-loan", "school", "education",
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
        // Retail / hospitality / service industry
        "retail", "merchandising", "store-operations", "point-of-sale", "ecommerce",
        "hospitality", "hotel-operations", "front-desk", "concierge", "housekeeping",
        "restaurant", "food-service", "menu", "kitchen-operations",
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
        // Status flags
        "urgent", "to-review", "follow-up", "paid", "unpaid", "overdue", "pending", "approved", "confidential"
    ]
}
