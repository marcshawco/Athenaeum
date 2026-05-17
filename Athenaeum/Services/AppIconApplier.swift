import SwiftUI
import AppKit

// MARK: - App icon variants
//
// Three pre-rendered marks from the brand kit. Stored as imagesets so the
// picker can preview them, and applied at runtime via
// `NSApplication.shared.applicationIconImage` so the Dock + Cmd-Tab tile
// update without a relaunch. Re-applied on every cold start from
// `AthenaeumApp` so the user's choice survives quits.

enum AppIconVariant: String, CaseIterable, Identifiable, Sendable {
    case ink
    case inverse
    case forest

    var id: String { rawValue }

    /// Imageset name in `Assets.xcassets`. (We keep this string-based
    /// lookup rather than the Xcode-generated `ImageResource.brandMark`
    /// symbol because the type-safe symbols only resolve once the
    /// catalog has been compiled at least once, and the strings here
    /// are the source-of-truth identifiers that the catalog's
    /// imagesets are named after — a rename of the imageset is the
    /// signal to update both sides in lockstep.)
    var assetName: String {
        switch self {
        case .ink:     "BrandMark"
        case .inverse: "BrandMarkInverse"
        case .forest:  "BrandMarkForest"
        }
    }

    var displayName: String {
        switch self {
        case .ink:     "Ink"
        case .inverse: "Paper"
        case .forest:  "Forest"
        }
    }

    var helpText: String {
        switch self {
        case .ink:     "Deep ink on cream — the default brand mark."
        case .inverse: "Cream Æ on light paper, for muted Docks."
        case .forest:  "Pale moss Æ on deep forest green."
        }
    }
}

// MARK: - Applier

enum AppIconApplier {
    /// Resolve the imageset to an NSImage and push it onto the app instance.
    /// Safe to call from anywhere; falls back silently if the imageset isn't
    /// present (e.g. a future variant ships ahead of its asset).
    @MainActor
    static func apply(_ variant: AppIconVariant) {
        if let image = NSImage(named: variant.assetName) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    /// Read the persisted choice from @AppStorage's underlying key and apply
    /// it. Called once at launch from `AthenaeumApp` so the user's choice
    /// survives quit/relaunch.
    @MainActor
    static func applyFromDefaults() {
        let raw = UserDefaults.standard.string(forKey: "appIconVariant") ?? AppIconVariant.ink.rawValue
        let variant = AppIconVariant(rawValue: raw) ?? .ink
        apply(variant)
    }
}
