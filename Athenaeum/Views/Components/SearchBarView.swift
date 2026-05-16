import SwiftUI

struct SearchBarView: View {
    @Binding var text: String
    var placeholder: String = "Search documents..."
    var onCommit: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Japandi.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Japandi.Colors.textTertiaryFB)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
                .focused($isFocused)
                .onSubmit { onCommit?() }

            if !text.isEmpty {
                Button {
                    withAnimation(Japandi.Motion.snappy) { text = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, Japandi.Spacing.sm)
        .frame(height: 34)
        .background(Japandi.Colors.surfaceRaisedFB)
        .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Japandi.Radius.md, style: .continuous)
                .strokeBorder(
                    isFocused
                        ? Japandi.Colors.accentFallback.opacity(0.5)
                        : Japandi.Colors.borderFallback.opacity(0.9),
                    lineWidth: isFocused ? 0.75 : 0.5
                )
        )
        .japandiShadow(isFocused ? Japandi.Shadow.subtle : ShadowStyle(color: .clear, radius: 0, x: 0, y: 0))
        .animation(Japandi.Motion.snappy, value: isFocused)
    }
}
