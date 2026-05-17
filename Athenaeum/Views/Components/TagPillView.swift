import SwiftUI

struct TagPillView: View {
    let name: String
    let colorHex: String
    var isSelected: Bool = false
    var onTap: (() -> Void)?
    var onRemove: (() -> Void)?

    private var tagColor: Color {
        Color(hex: UInt(colorHex, radix: 16) ?? 0x2A639D)
    }

    var body: some View {
        HStack(spacing: Japandi.Spacing.xxs) {
            Circle()
                .fill(tagColor)
                .frame(width: 5, height: 5)

            Text(name)
                .font(Japandi.Typography.caption)
                .foregroundStyle(isSelected ? .white : Japandi.Colors.textSecondaryFB)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : Japandi.Colors.textTertiaryFB)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Japandi.Spacing.xs)
        .padding(.vertical, Japandi.Spacing.xxs)
        .background(
            isSelected
                ? tagColor.opacity(0.82)
                : tagColor.opacity(0.08)
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(tagColor.opacity(isSelected ? 0.0 : 0.18), lineWidth: 0.5)
        )
        .contentShape(Capsule())
        .onTapGesture { onTap?() }
        // Accessibility: the visual is custom-styled rather than a SwiftUI
        // Button, but it IS interactive when `onTap` is bound. Surface
        // that to VoiceOver + Full Keyboard Access.
        .modifier(TagPillAccessibilityModifier(name: name, isSelected: isSelected, isInteractive: onTap != nil))
    }
}

private struct TagPillAccessibilityModifier: ViewModifier {
    let name: String
    let isSelected: Bool
    let isInteractive: Bool

    func body(content: Content) -> some View {
        if isInteractive {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Tag \(name)"))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .focusable()
        } else {
            content
                .accessibilityLabel(Text("Tag \(name)"))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}
