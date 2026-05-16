import SwiftUI

// MARK: - AI Rename Review Sheet
//
// Modal presented after the user picks "Rename with AI" on one or more
// documents. The model has already read the docs and proposed new titles;
// this sheet lets the user review them all at once, edit any field inline,
// or cancel out cleanly. We deliberately never auto-apply renames — that
// would be hostile when the model misreads.

struct AIRenameSheet: View {
    @Binding var suggestions: [ContentView.AIRenameSuggestion]
    let isLoading: Bool
    let onApplyAll: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.md) {
            header

            if isLoading {
                loadingState
            } else if suggestions.isEmpty {
                emptyState
            } else {
                list
            }

            Divider().foregroundStyle(Japandi.Colors.borderFallback)

            footer
        }
        .padding(Japandi.Spacing.lg)
        .frame(width: 560, height: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Auto Name")
                .font(.system(size: 18, weight: .medium, design: .serif))
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
            Text("The local model read each document and proposed a clean name. Review, edit, or cancel.")
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
        }
    }

    private var loadingState: some View {
        VStack(spacing: Japandi.Spacing.sm) {
            ProgressView()
                .scaleEffect(0.85)
            Text("Reading documents…")
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Japandi.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .ultraLight))
                .foregroundStyle(Japandi.Colors.borderFallback)
            Text("No suggestions yet")
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Japandi.Spacing.xs) {
                ForEach($suggestions) { $row in
                    suggestionRow($row)
                }
            }
        }
    }

    private func suggestionRow(_ row: Binding<ContentView.AIRenameSuggestion>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.wrappedValue.originalTitle)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Japandi.Colors.accentFallback)
                TextField("New title", text: row.accepted)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
            }
        }
        .padding(.horizontal, Japandi.Spacing.sm)
        .padding(.vertical, 10)
        .background(Japandi.Colors.surfaceRaisedFB)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Japandi.Colors.borderFallback, lineWidth: 0.5)
        )
    }

    private var footer: some View {
        HStack {
            if !suggestions.isEmpty {
                Text("\(suggestions.count) suggestion\(suggestions.count == 1 ? "" : "s")")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }
            Spacer()
            Button("Cancel") { onCancel() }
                .buttonStyle(.plain)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)
                .keyboardShortcut(.cancelAction)
            Button(suggestions.count == 1 ? "Apply" : "Apply all") {
                onApplyAll()
            }
            .buttonStyle(.borderedProminent)
            .tint(Japandi.Colors.accentFallback)
            .keyboardShortcut(.defaultAction)
            .disabled(suggestions.isEmpty || isLoading)
        }
    }
}
