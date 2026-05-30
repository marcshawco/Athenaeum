import SwiftUI

struct AIDisclaimerView: View {
    enum Tone {
        case standard
        case inspector
    }

    static let text = "ATHENS can make mistakes.\nVerify against source docs.\nNot legal, medical, tax, or financial advice."

    var tone: Tone = .standard
    var isFramed = true

    var body: some View {
        HStack(alignment: .top, spacing: Japandi.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(accentColor)
                .frame(width: 16, alignment: .center)
                .accessibilityHidden(true)

            Text(Self.text)
                .font(Japandi.Typography.caption)
                .foregroundStyle(textColor)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(isFramed ? Japandi.Spacing.sm : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isFramed {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
            }
        }
        .overlay {
            if isFramed {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.text.replacingOccurrences(of: "\n", with: " "))
    }

    private var textColor: Color {
        switch tone {
        case .standard: Japandi.Colors.textSecondaryFB
        case .inspector: Japandi.Colors.inspectorInk2
        }
    }

    private var accentColor: Color {
        switch tone {
        case .standard: Japandi.Colors.warmFallback
        case .inspector: Japandi.Colors.inspectorAccent
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .standard: Japandi.Colors.warmSoftFallback.opacity(0.35)
        case .inspector: Color.white.opacity(0.045)
        }
    }

    private var borderColor: Color {
        switch tone {
        case .standard: Japandi.Colors.warmFallback.opacity(0.22)
        case .inspector: Japandi.Colors.inspectorRule
        }
    }
}
