import MuxyShared
import SwiftUI

struct TabCell: View {
    static let minWidth: CGFloat = 44
    static let maxWidth: CGFloat = 200
    static let titleHideThreshold: CGFloat = 80

    let tab: PaneTabStrip.TabSnapshot
    let active: Bool
    let paneFocused: Bool
    var hasUnread: Bool = false
    var isAnyDragging: Bool = false
    var shortcutIndex: Int?
    var closableOthersCount: Int = 0
    var closableLeftCount: Int = 0
    var closableRightCount: Int = 0
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void
    let onCloseLeft: () -> Void
    let onCloseRight: () -> Void
    let onCreateLeft: () -> Void
    let onCreateRight: () -> Void
    let onTogglePin: () -> Void
    let onSetCustomTitle: (String?) -> Void
    let onSetColorID: (String?) -> Void
    @State
    private var hovered = false
    @State
    private var isRenaming = false
    @State
    private var renameText = ""
    @State
    private var showColorPicker = false
    @State
    private var measuredWidth: CGFloat = TabCell.maxWidth
    @FocusState
    private var renameFieldFocused: Bool

    private var titleHidden: Bool {
        measuredWidth < Self.titleHideThreshold
    }

    private var tabColor: Color? {
        ProjectIconColor.color(for: tab.colorID)
    }

    private var tabBackground: Color {
        guard let tabColor else {
            return active ? MuxyTheme.surface : .clear
        }
        let opacity = if active { 0.18 } else if hovered { 0.08 } else { 0.04 }
        return tabColor.opacity(opacity)
    }

    private var bottomAccentColor: Color? {
        if active, paneFocused {
            return tabColor ?? MuxyTheme.accent
        }
        if let tabColor, !active {
            return tabColor
        }
        return nil
    }

    private var showBadge: Bool {
        guard let shortcutIndex,
              let action = ShortcutAction.tabAction(for: shortcutIndex)
        else { return false }
        return ModifierKeyMonitor.shared.isHolding(
            modifiers: KeyBindingStore.shared.combo(for: action).modifiers
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                tabIconView
                    .foregroundStyle(active ? MuxyTheme.fg : MuxyTheme.fgMuted)
                    .opacity(titleHidden && hovered && !tab.isPinned ? 0 : 1)
                    .overlay(alignment: .topTrailing) {
                        if hasUnread, !active {
                            Circle()
                                .fill(MuxyTheme.accent)
                                .frame(width: 6, height: 6)
                                .offset(x: 3, y: -3)
                        }
                    }

                if isRenaming {
                    TextField("", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(MuxyTheme.fg)
                        .focused($renameFieldFocused)
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                } else if !titleHidden {
                    Text(tab.title)
                        .font(.system(size: 12))
                        .foregroundStyle(active ? MuxyTheme.fg : MuxyTheme.fgMuted)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .padding(.leading, titleHidden ? 0 : 12)
            .padding(.trailing, titleHidden ? 0 : 28)
            .frame(maxWidth: .infinity, alignment: titleHidden ? .center : .leading)
            .frame(height: 32)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: TabWidthPreferenceKey.self, value: geo.size.width)
                }
            }
            .onPreferenceChange(TabWidthPreferenceKey.self) { measuredWidth = $0 }
            .overlay(alignment: titleHidden ? .center : .trailing) {
                if !tab.isPinned {
                    let visible = titleHidden ? hovered : (active || hovered)
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MuxyTheme.fgDim)
                        .padding(.trailing, titleHidden ? 0 : 10)
                        .opacity(visible ? 1 : 0)
                        .onTapGesture(perform: onClose)
                        .accessibilityLabel("Close Tab")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .overlay {
                if showBadge, let shortcutIndex,
                   let action = ShortcutAction.tabAction(for: shortcutIndex)
                {
                    ShortcutBadge(label: KeyBindingStore.shared.combo(for: action).displayString)
                }
            }
            .overlay(alignment: .bottom) {
                if let accentColor = bottomAccentColor {
                    Rectangle()
                        .fill(accentColor)
                        .frame(height: 2)
                        .accessibilityHidden(true)
                }
            }
            .background(tabBackground)
            .contentShape(Rectangle())
            .onHover { hovering in
                guard !isAnyDragging else { return }
                hovered = hovering
            }
            .onChange(of: isAnyDragging) { _, dragging in
                if dragging { hovered = false }
            }
            .overlay {
                if !tab.isPinned {
                    MiddleClickView(action: onClose)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if !tab.isPinned {
                    DoubleClickView(action: startRename)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tabAccessibilityLabel)
            .accessibilityAddTraits(active ? .isSelected : [])
            .accessibilityAddTraits(.isButton)
            .contextMenu {
                Button("New Tab to the Left") { onCreateLeft() }
                Button("New Tab to the Right") { onCreateRight() }
                Divider()
                Button("Close Other Tabs") { onCloseOthers() }
                    .disabled(closableOthersCount == 0)
                Button("Close Tabs to the Left") { onCloseLeft() }
                    .disabled(closableLeftCount == 0)
                Button("Close Tabs to the Right") { onCloseRight() }
                    .disabled(closableRightCount == 0)
                Divider()
                Button("Rename Tab") { startRename() }
                if tab.hasCustomTitle {
                    Button("Reset Title") { onSetCustomTitle(nil) }
                }
                Button("Set Tab Color...") { showColorPicker = true }
                if tab.colorID != nil {
                    Button("Reset Tab Color") { onSetColorID(nil) }
                }
                Divider()
                Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") {
                    onTogglePin()
                }
                if !tab.isPinned {
                    Divider()
                    Button("Close Tab") { onClose() }
                }
            }
            .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                ProjectIconColorPicker(title: "Tab Color", selectedID: tab.colorID) { id in
                    onSetColorID(id)
                    showColorPicker = false
                }
            }

            Rectangle().fill(MuxyTheme.border).frame(width: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .renameActiveTab)) { _ in
            guard active else { return }
            startRename()
        }
    }

    private func startRename() {
        renameText = tab.title
        isRenaming = true
        renameFieldFocused = true
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        onSetCustomTitle(trimmed.isEmpty ? nil : trimmed)
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
    }

    private var tabAccessibilityLabel: String {
        var label = tab.title
        switch tab.kind {
        case .terminal: label += ", Terminal"
        case .vcs: label += ", Source Control"
        case .editor: label += ", Editor"
        case .diffViewer: label += ", Diff Viewer"
        }
        if tab.isPinned { label += ", Pinned" }
        if hasUnread { label += ", Unread" }
        return label
    }

    @ViewBuilder
    private var tabIconView: some View {
        if tab.isPinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 10, weight: .semibold))
        } else if tab.kind == .vcs {
            FileDiffIcon()
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 12)
        } else if tab.kind == .editor {
            Image(systemName: "pencil.line")
                .font(.system(size: 12, weight: .semibold))
        } else if tab.kind == .diffViewer {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 11, weight: .semibold))
        } else {
            Image(systemName: "terminal")
                .font(.system(size: 12, weight: .semibold))
        }
    }
}
