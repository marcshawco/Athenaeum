import SwiftUI
import AppKit

// MARK: - Japandi Design System — Stillwater Warm
// Cream paper, deep moss, clay accents. A commonplace-book hush.

enum Japandi {

    // MARK: - Color Palette

    enum Colors {
        // Backgrounds
        static let background    = Color("Background",    bundle: nil)
        static let surface       = Color("Surface",       bundle: nil)
        static let surfaceRaised = Color("SurfaceRaised", bundle: nil)

        // Semantic
        static let accent       = Color("BrandAccent",  bundle: nil)
        static let accentMuted  = Color("AccentMuted",  bundle: nil)

        // Text
        static let textPrimary   = Color("TextPrimary",   bundle: nil)
        static let textSecondary = Color("TextSecondary", bundle: nil)
        static let textTertiary  = Color("TextTertiary",  bundle: nil)

        // Utility
        static let border       = Color("Border",       bundle: nil)
        static let destructive  = Color("Destructive",  bundle: nil)
        static let success      = Color("Success",      bundle: nil)

        // Stillwater Warm palette.
        // Light: FBFAF7 paper · 3E5C4A moss · B98A4F clay · 211F1B ink.
        // Dark : 1A1614 charcoal · C8D4BE pale moss · EDEFE6 paper-ink.
        static let bgFallback          = Color(light: 0xFBFAF7, dark: 0x1A1614)
        static let surfaceFallback     = Color(light: 0xF4F2EC, dark: 0x231F1B)
        static let surfaceRaisedFB     = Color(light: 0xFFFFFF, dark: 0x2A2521)
        static let accentFallback      = Color(light: 0x3E5C4A, dark: 0xC8D4BE)
        static let accentMutedFallback = Color(light: 0x8AA89A, dark: 0x8AA89A)
        static let textPrimaryFB       = Color(light: 0x211F1B, dark: 0xEDEFE6)
        static let textSecondaryFB     = Color(light: 0x5A554D, dark: 0xB7C2B0)
        static let textTertiaryFB      = Color(light: 0x9C968B, dark: 0x8FA395)
        static let borderFallback      = Color(light: 0xE6E1D5, dark: 0x3A332B)
        // inkFallback — deepest ink, used for glyph chips and brand mark.
        static let inkFallback         = Color(light: 0x211F1B, dark: 0xEDEFE6)
        // mineralFallback — warm clay (OCR badges, secondary accent).
        static let mineralFallback     = Color(light: 0xB98A4F, dark: 0xB98A4F)
        // lacquerFallback — warm dark (status/destructive subtle).
        static let lacquerFallback     = Color(light: 0x7A5226, dark: 0xC8A37A)
        // washFallback — accent soft (chip backgrounds, selected wash).
        static let washFallback        = Color(light: 0xE6EBE3, dark: 0x243A2D)

        // Dark moss inspector (right-rail). Used regardless of light/dark mode
        // — the inspector is always the deep moss pane.
        static let inspectorBg         = Color(hex: 0x243A2D)
        static let inspectorInk        = Color(hex: 0xEDEFE6)
        static let inspectorInk2       = Color(hex: 0xB7C2B0)
        static let inspectorInk3       = Color(hex: 0x8FA395)
        static let inspectorAccent     = Color(hex: 0xC8D4BE)
        static let inspectorRule       = Color(hex: 0xEDEFE6).opacity(0.08)

        // Clay/gold warm secondary (OCR badges, warm pills).
        static let warmFallback        = Color(light: 0xB98A4F, dark: 0xC8A37A)
        static let warmSoftFallback    = Color(light: 0xF3E6D3, dark: 0x3A2D1A)
    }

    // MARK: - Typography

    enum Typography {
        static let largeTitle = Font.system(size: 34, weight: .thin,    design: .serif)
        static let title      = Font.system(size: 22, weight: .light,   design: .serif)
        static let headline   = Font.system(size: 14, weight: .medium,  design: .default)
        static let body       = Font.system(size: 13, weight: .regular, design: .default)
        static let caption    = Font.system(size: 11, weight: .regular, design: .default)
        static let mono       = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let eyebrow    = Font.system(size: 9,  weight: .medium,  design: .default)
    }

    // MARK: - Spacing (8-pt grid)

    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs:  CGFloat = 4
        static let xs:   CGFloat = 8
        static let sm:   CGFloat = 12
        static let md:   CGFloat = 16
        static let lg:   CGFloat = 24
        static let xl:   CGFloat = 32
        static let xxl:  CGFloat = 48
        static let xxxl: CGFloat = 64
    }

    // MARK: - Radii

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
    }

    // MARK: - Shadows

    enum Shadow {
        static let subtle = ShadowStyle(color: .black.opacity(0.025), radius: 8,  x: 0, y: 3)
        static let card   = ShadowStyle(color: .black.opacity(0.050), radius: 16, x: 0, y: 8)
        static let lifted = ShadowStyle(color: .black.opacity(0.090), radius: 24, x: 0, y: 14)
    }

    // MARK: - Animation

    enum Motion {
        static let snappy   = Animation.spring(response: 0.3, dampingFraction: 0.85)
        static let gentle   = Animation.spring(response: 0.5, dampingFraction: 0.8)
        static let duration = Animation.easeInOut(duration: 0.25)
    }

    // MARK: - Layout

    enum Layout {
        static let sidebarWidth: CGFloat    = 224
        static let listMinWidth: CGFloat    = 300
        static let detailMinWidth: CGFloat  = 400
        static let windowMinWidth: CGFloat  = 960
        static let windowMinHeight: CGFloat = 640
    }
}

// MARK: - Shadow Style

struct ShadowStyle: Sendable {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Extensions

extension View {
    func japandiShadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    func japandiCard() -> some View {
        self
            .background(Japandi.Colors.surfaceRaisedFB)
            .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Japandi.Radius.md, style: .continuous)
                    .strokeBorder(Japandi.Colors.borderFallback.opacity(0.85), lineWidth: 0.5)
            )
            .japandiShadow(Japandi.Shadow.subtle)
    }

    func japandiCardHover(_ isHovered: Bool) -> some View {
        self
            .background(Japandi.Colors.surfaceRaisedFB)
            .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Japandi.Radius.md, style: .continuous)
                    .strokeBorder(
                        isHovered
                            ? Japandi.Colors.accentFallback.opacity(0.5)
                            : Japandi.Colors.borderFallback.opacity(0.85),
                        lineWidth: isHovered ? 0.75 : 0.5
                    )
            )
            .japandiShadow(isHovered ? Japandi.Shadow.card : Japandi.Shadow.subtle)
            .animation(Japandi.Motion.snappy, value: isHovered)
    }

    func premiumPane() -> some View {
        self
            .background(Japandi.Colors.surfaceRaisedFB)
            .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Japandi.Radius.md, style: .continuous)
                    .strokeBorder(Japandi.Colors.borderFallback.opacity(0.85), lineWidth: 0.5)
            )
            .japandiShadow(Japandi.Shadow.subtle)
    }
}

// MARK: - Text Extensions

extension Text {
    func eyebrowStyle(_ color: Color = Japandi.Colors.textTertiaryFB) -> some View {
        self.font(Japandi.Typography.eyebrow)
            .textCase(.uppercase)
            .tracking(2)
            .foregroundStyle(color)
    }
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(light: UInt, dark: UInt, opacity: Double = 1.0) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return NSColor(hex: match == .darkAqua ? dark : light, opacity: opacity)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: opacity
        )
    }
}
