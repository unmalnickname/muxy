import AppKit
import SwiftUI

struct ExpandedWorktreeRow: View {
    let projectID: UUID
    let worktree: Worktree
    let selected: Bool
    let projectActive: Bool
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onRemove: (() -> Void)?

    @State private var hovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool

    private var displayName: String {
        if worktree.isPrimary, worktree.name.isEmpty { return "main" }
        return worktree.name
    }

    private var activeStyle: Bool { selected && projectActive }

    private var branchLabel: String? {
        guard !worktree.isPrimary else { return nil }
        guard let branch = worktree.branch, !branch.isEmpty else { return nil }
        guard branch.caseInsensitiveCompare(displayName) != .orderedSame else { return nil }
        return branch
    }

    var body: some View {
        HStack(spacing: 6) {
            leadingIndicator

            if isRenaming {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuxyTheme.fg)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(displayName)
                            .font(.system(size: 12, weight: activeStyle ? .semibold : .regular))
                            .foregroundStyle(MuxyTheme.fg)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if worktree.isPrimary {
                            PrimaryBadge()
                        }
                    }

                    if let branch = branchLabel {
                        Text(branch)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(MuxyTheme.fg)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer(minLength: 2)

            worktreeUnreadBadge

            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(MuxyTheme.accent)
                .frame(width: 18, height: 18)
                .opacity(selected ? 1 : 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovered = $0 }
        .onTapGesture {
            guard !isRenaming else { return }
            onSelect()
        }
        .contextMenu {
            if worktree.isPrimary {
                Text("Primary worktree").font(.system(size: 11))
            } else if let onRemove {
                Button("Rename") { startRename() }
                Divider()
                Button("Remove", role: .destructive, action: onRemove)
            } else {
                Button("Rename") { startRename() }
                Divider()
                Text("External worktree").font(.system(size: 11))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(worktreeAccessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAddTraits(.isButton)
    }

    private var worktreeAccessibilityLabel: String {
        var label = displayName
        if worktree.isPrimary { label += ", primary" }
        if let branch = branchLabel { label += ", branch: \(branch)" }
        return label
    }

    @ViewBuilder
    private var worktreeUnreadBadge: some View {
        let unread = NotificationStore.shared.unreadCount(for: projectID, worktreeID: worktree.id)
        if unread > 0 {
            NotificationBadge(count: unread)
        }
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if activeStyle {
            Circle()
                .fill(MuxyTheme.accent)
                .frame(width: 5, height: 5)
        } else {
            Circle()
                .stroke(MuxyTheme.fgDim.opacity(0.35), lineWidth: 1)
                .frame(width: 5, height: 5)
        }
    }

    private var rowBackground: AnyShapeStyle {
        if activeStyle { return AnyShapeStyle(MuxyTheme.accentSoft) }
        if hovered { return AnyShapeStyle(MuxyTheme.hover) }
        return AnyShapeStyle(Color.clear)
    }

    private func startRename() {
        renameText = worktree.name
        isRenaming = true
        renameFieldFocused = true
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { onRename(trimmed) }
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
    }
}
