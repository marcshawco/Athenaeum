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
        // 300-term controlled vocabulary for adult and small-business documents.
        "identity", "passport", "drivers-license", "social-security", "birth-certificate", "marriage-certificate", "divorce", "adoption",
        "citizenship", "visa", "immigration", "address", "contact", "emergency-contact", "beneficiary", "estate",
        "will", "trust", "power-of-attorney", "notary", "legal", "court", "attorney", "claim",
        "settlement", "affidavit", "subpoena", "judgment", "permit", "license", "medical", "dental",
        "vision", "prescription", "pharmacy", "lab-results", "imaging", "vaccination", "insurance-card", "benefits",
        "explanation-of-benefits", "diagnosis", "treatment", "referral", "provider", "patient", "health-record", "therapy",
        "mental-health", "veterinary", "pet", "bank-statement", "checking", "savings", "credit-card", "debit-card",
        "transaction", "deposit", "withdrawal", "transfer", "loan", "mortgage", "refinance", "interest",
        "investment", "brokerage", "retirement", "ira", "401k", "pension", "dividend", "statement",
        "budget", "expense", "receipt", "invoice", "bill", "payment", "refund", "reimbursement",
        "tax", "w-2", "1099", "1040", "schedule-c", "deduction", "charitable-donation", "property-tax",
        "sales-tax", "payroll-tax", "estimated-tax", "tax-return", "tax-notice", "irs", "bookkeeping", "accounting",
        "ledger", "balance-sheet", "profit-loss", "cash-flow", "accounts-payable", "accounts-receivable", "payroll", "paystub",
        "timesheet", "contractor", "employee", "offer-letter", "onboarding", "handbook", "performance-review", "termination",
        "resume", "cover-letter", "reference-check", "background-check", "training", "certification", "transcript", "diploma",
        "tuition", "scholarship", "financial-aid", "student-loan", "school", "education", "contract", "agreement",
        "nda", "statement-of-work", "proposal", "quote", "estimate", "purchase-order", "work-order", "change-order",
        "scope", "deliverables", "milestone", "invoice-terms", "signature", "signed", "renewal", "amendment",
        "addendum", "termination-clause", "lease", "rent", "tenant", "landlord", "property", "real-estate",
        "deed", "title", "appraisal", "inspection", "insurance", "auto-insurance", "home-insurance", "renters-insurance",
        "life-insurance", "business-insurance", "policy", "premium", "deductible", "coverage", "accident", "repair",
        "warranty", "service-record", "maintenance", "vehicle", "registration", "vin", "title-transfer", "parking",
        "toll", "ticket", "utilities", "electric", "gas", "water", "internet", "phone",
        "mobile", "subscription", "membership", "cancellation", "account", "login", "password", "confirmation",
        "receipt-email", "correspondence", "letter", "email", "memo", "notice", "reminder", "invitation",
        "announcement", "newsletter", "application", "business-plan", "marketing", "sales", "client", "customer",
        "lead", "vendor", "supplier", "partner", "project", "meeting-notes", "agenda", "minutes",
        "report", "presentation", "spreadsheet", "dashboard", "analytics", "inventory", "shipping", "delivery",
        "packing-slip", "bill-of-lading", "order", "fulfillment", "return", "rma", "procurement", "compliance",
        "procedure", "standard-operating-procedure", "audit", "safety", "incident", "security", "privacy", "data",
        "gdpr", "hipaa", "accessibility", "risk", "assessment", "checklist", "form", "template",
        "manual", "guide", "instructions", "specification", "requirements", "research", "article", "whitepaper",
        "travel", "itinerary", "boarding-pass", "flight", "hotel", "reservation", "rental-car", "passport-copy",
        "visa-copy", "event", "conference", "workshop", "mileage", "per-diem", "home", "household",
        "moving", "storage", "renovation", "contractor-bid", "blueprint", "floor-plan", "hoa", "mortgage-statement",
        "escrow", "utilities-bill", "family", "childcare", "daycare", "eldercare", "consent-form", "document",
        "pdf", "scan", "image", "urgent", "to-review", "follow-up", "paid", "unpaid",
        "overdue", "pending", "approved", "confidential"
    ]
}
