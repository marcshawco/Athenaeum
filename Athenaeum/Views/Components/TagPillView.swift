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
    }
}
