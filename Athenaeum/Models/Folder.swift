import Foundation
import SwiftData

// MARK: - Folder
//
// User-curated grouping of documents. Distinct from tags (which are
// many-to-many descriptive labels) and the auto-derived "By Category"
// view (which uses the 500-type taxonomy). A folder is a stable shelf
// the user puts things on.
//
// Documents can live in multiple folders simultaneously — SwiftData
// many-to-many. Removing a folder doesn't delete its documents.

@Model
final class Folder {
    @Attribute(.unique) var id: UUID
    var name: String
    /// 6-character hex (no #) so the existing `Color(hex:)` initializer
    /// can render the dot consistently with how tags render.
    var colorHex: String
    var createdAt: Date
    var modifiedAt: Date

    /// Members. Inverse declared on `Document.folders` so SwiftData keeps
    /// the link table in sync when either side mutates.
    @Relationship(inverse: \Document.folders)
    var documents: [Document]?

    init(name: String, colorHex: String = Folder.defaultColors.randomElement() ?? "B98A4F") {
        self.id = UUID()
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.colorHex = colorHex
        self.createdAt = .now
        self.modifiedAt = .now
    }

    /// Curated palette — drawn from the Stillwater Warm palette so folder
    /// dots feel like part of the brand instead of a random color picker.
    static let defaultColors: [String] = [
        "3E5C4A", // moss accent
        "8AA89A", // pale moss
        "B98A4F", // clay
        "C8A37A", // light clay
        "7A5226", // deep clay
        "5A554D", // ink secondary
        "9C968B", // ink tertiary
        "243A2D", // deep moss
    ]
}
