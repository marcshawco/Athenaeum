import SwiftUI

// MARK: - Keyboard Shortcut Handler
// Centralizes keyboard shortcut handling across the app.

struct KeyboardShortcutHandler: ViewModifier {
    @Binding var selectedSection: SidebarSection
    var onImport: () -> Void
    var onSearch: () -> Void

    func body(content: Content) -> some View {
        content
            .keyboardShortcut("1", modifiers: [.command]) // All Documents
            .background {
                // Hidden buttons to catch shortcuts
                Group {
                    Button("") { selectedSection = .all }
                        .keyboardShortcut("1", modifiers: [.command])
                    Button("") { selectedSection = .recent }
                        .keyboardShortcut("2", modifiers: [.command])
                    Button("") { selectedSection = .chat }
                        .keyboardShortcut("3", modifiers: [.command])
                    Button("") { selectedSection = .models }
                        .keyboardShortcut("4", modifiers: [.command])
                    Button("") { onImport() }
                        .keyboardShortcut("i", modifiers: [.command])
                    Button("") { onSearch() }
                        .keyboardShortcut("f", modifiers: [.command])
                }
                .frame(width: 0, height: 0)
                .opacity(0)
            }
    }
}

// MARK: - Batch Action Toolbar

struct BatchActionToolbar: View {
    let selectedCount: Int
    var onAddTag: () -> Void
    var onExport: () -> Void
    var onReprocess: () -> Void
    var onDelete: () -> Void
    var onClearSelection: () -> Void

    var body: some View {
        if selectedCount > 0 {
            HStack(spacing: Japandi.Spacing.md) {
                // Selection count
                HStack(spacing: Japandi.Spacing.xxs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Japandi.Colors.accentFallback)
                    Text("\(selectedCount) selected")
                        .font(Japandi.Typography.body)
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                }

                Spacer()

                // Actions
                Group {
                    Button(action: onAddTag) {
                        Label("Tag", systemImage: "tag")
                    }

                    Button(action: onExport) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }

                    Button(action: onReprocess) {
                        Label("Reprocess", systemImage: "arrow.clockwise")
                    }

                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .font(Japandi.Typography.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onClearSelection) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Japandi.Spacing.md)
            .padding(.vertical, Japandi.Spacing.xs)
            .background(Japandi.Colors.surfaceFallback)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
