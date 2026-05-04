import MuxyShared
import SwiftUI

struct PaneTabStrip: View {
    struct TabSnapshot: Identifiable {
        let id: UUID
        let title: String
        let kind: TerminalTab.Kind
        let isPinned: Bool
        let hasCustomTitle: Bool
        let colorID: String?
    }

    let areaID: UUID
    let tabs: [TabSnapshot]
    let activeTabID: UUID?
    let isFocused: Bool
    var isWindowTitleBar: Bool = false
    var showVCSButton = true
    var showDevelopmentBadge = false
    var openInIDEProjectPath: String?
    var openInIDEFilePath: String?
    var openInIDECursorProvider: () -> (line: Int?, column: Int?) = { (nil, nil) }
    let projectID: UUID
    let onSelectTab: (UUID) -> Void
    let onCreateTab: () -> Void
    let onCreateVCSTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onCloseOtherTabs: (UUID) -> Void
    let onCloseTabsToLeft: (UUID) -> Void
    let onCloseTabsToRight: (UUID) -> Void
    let onSplit: (SplitDirection) -> Void
    let onDropAction: (TabDragCoordinator.DropResult) -> Void
    let onCreateTabAdjacent: (UUID, TabArea.InsertSide) -> Void
    let onTogglePin: (UUID) -> Void
    let onSetCustomTitle: (UUID, String?) -> Void
    let onSetColorID: (UUID, String?) -> Void
    let onReorderTab: (IndexSet, Int) -> Void
    @Environment(TabDragCoordinator.self) private var dragCoordinator
    @State private var dragState = TabDragState()

    static func snapshots(from tabs: [TerminalTab]) -> [TabSnapshot] {
        tabs.map { tab in
            TabSnapshot(
                id: tab.id,
                title: tab.title,
                kind: tab.kind,
                isPinned: tab.isPinned,
                hasCustomTitle: tab.customTitle != nil,
                colorID: tab.colorID
            )
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    tabRow(availableWidth: geo.size.width)
                        .frame(minWidth: geo.size.width, alignment: .leading)
                        .background(WindowDragRepresentable(alwaysEnabled: isWindowTitleBar))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)

            HStack(spacing: 0) {
                if showDevelopmentBadge {
                    developmentBadge
                        .padding(.trailing, 6)
                }
                HealthIconButton {
                    NotificationCenter.default.post(name: .toggleHealth, object: nil)
                }
                .help("Project Health")
                Button {
                    NotificationCenter.default.post(name: .togglePipeline, object: nil)
                } label: {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 12))
                        .foregroundStyle(MuxyTheme.fgDim)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Pipeline")
                if isWindowTitleBar {
                    OpenInIDEControl(
                        projectPath: openInIDEProjectPath,
                        filePath: openInIDEFilePath,
                        cursorProvider: openInIDECursorProvider
                    )
                    LayoutPickerMenu(projectID: projectID)
                }
                if isWindowTitleBar, let version = UpdateService.shared.availableUpdateVersion {
                    UpdateBadge(version: version) {
                        UpdateService.shared.checkForUpdates()
                    }
                    .padding(.trailing, 4)
                }
                IconButton(symbol: "square.split.2x1", accessibilityLabel: "Split Right") { onSplit(.horizontal) }
                    .help(shortcutTooltip("Split Right", for: .splitRight))
                IconButton(symbol: "square.split.1x2", accessibilityLabel: "Split Down") { onSplit(.vertical) }
                    .help(shortcutTooltip("Split Down", for: .splitDown))
                IconButton(symbol: "plus", accessibilityLabel: "New Tab") { onCreateTab() }
                    .help(shortcutTooltip("New Tab", for: .newTab))
                if showVCSButton {
                    IconButton(symbol: "doc.text", size: 12, accessibilityLabel: "Quick Open") {
                        NotificationCenter.default.post(name: .quickOpen, object: nil)
                    }
                    .help(shortcutTooltip("Quick Open", for: .quickOpen))
                    FileDiffIconButton(action: onCreateVCSTab)
                        .help(shortcutTooltip("Source Control", for: .openVCSTab))
                    FileTreeIconButton {
                        NotificationCenter.default.post(name: .toggleFileTree, object: nil)
                    }
                    .help(shortcutTooltip("File Tree", for: .toggleFileTree))
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .fixedSize(horizontal: true, vertical: false)
            .background(WindowDragRepresentable(alwaysEnabled: isWindowTitleBar))
        }
        .frame(height: 32)
        .onPreferenceChange(TabFramePreferenceKey.self) { frames in
            guard dragState.draggedID != nil else { return }
            dragState.frames = frames
        }
    }

    private func tabRow(availableWidth: CGFloat) -> some View {
        let count = max(tabs.count, 1)
        let effectiveWidth = availableWidth > 0 ? availableWidth : TabCell.maxWidth * CGFloat(count)
        let perTabIdeal = effectiveWidth / CGFloat(count)
        let perTabWidth = max(TabCell.minWidth, min(TabCell.maxWidth, perTabIdeal))

        return HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                TabCell(
                    tab: tab,
                    active: tab.id == activeTabID,
                    paneFocused: isFocused,
                    hasUnread: NotificationStore.shared.hasUnread(tabID: tab.id),
                    isAnyDragging: dragState.draggedID != nil,
                    shortcutIndex: index < 9 ? index + 1 : nil,
                    closableOthersCount: closableOthersCount(excluding: tab.id),
                    closableLeftCount: closableCount(leftOf: index),
                    closableRightCount: closableCount(rightOf: index),
                    onSelect: { onSelectTab(tab.id) },
                    onClose: { onCloseTab(tab.id) },
                    onCloseOthers: { onCloseOtherTabs(tab.id) },
                    onCloseLeft: { onCloseTabsToLeft(tab.id) },
                    onCloseRight: { onCloseTabsToRight(tab.id) },
                    onCreateLeft: { onCreateTabAdjacent(tab.id, .left) },
                    onCreateRight: { onCreateTabAdjacent(tab.id, .right) },
                    onTogglePin: { onTogglePin(tab.id) },
                    onSetCustomTitle: { onSetCustomTitle(tab.id, $0) },
                    onSetColorID: { onSetColorID(tab.id, $0) }
                )
                .frame(width: perTabWidth)
                .background {
                    if dragState.draggedID != nil {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: TabFramePreferenceKey.self,
                                value: [tab.id: geo.frame(in: .named(DragCoordinateSpace.mainWindow))]
                            )
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(DragCoordinateSpace.mainWindow))
                        .onChanged { value in
                            handleDragChanged(
                                tab: tab,
                                globalLocation: value.location,
                                dragStartGlobalLocation: value.startLocation
                            )
                        }
                        .onEnded { value in
                            handleDragEnded(
                                tab: tab,
                                globalLocation: value.location,
                                dragStartGlobalLocation: value.startLocation
                            )
                        }
                )
            }
        }
    }

    private func closableOthersCount(excluding tabID: UUID) -> Int {
        tabs.count(where: { $0.id != tabID && !$0.isPinned })
    }

    private func closableCount(leftOf index: Int) -> Int {
        tabs.prefix(index).count(where: { !$0.isPinned })
    }

    private func closableCount(rightOf index: Int) -> Int {
        tabs.suffix(from: index + 1).count(where: { !$0.isPinned })
    }

    private func shortcutTooltip(_ name: String, for action: ShortcutAction) -> String {
        "\(name) (\(KeyBindingStore.shared.combo(for: action).displayString))"
    }

    private var developmentBadge: some View {
        DebugButton()
    }

    private static let dragActivationDistance: CGFloat = 4

    private func handleDragChanged(
        tab: TabSnapshot,
        globalLocation: CGPoint,
        dragStartGlobalLocation: CGPoint
    ) {
        if !dragState.didSelect {
            dragState.didSelect = true
            onSelectTab(tab.id)
        }

        let dx = globalLocation.x - dragStartGlobalLocation.x
        let dy = globalLocation.y - dragStartGlobalLocation.y
        let distance = (dx * dx + dy * dy).squareRoot()

        if dragState.draggedID == nil {
            guard distance >= Self.dragActivationDistance else { return }
            dragState.draggedID = tab.id
            dragState.lastReorderTargetID = nil
        }

        if dragState.isInSplitMode {
            dragCoordinator.updatePosition(globalLocation)
            return
        }

        if abs(dy) > 24, !tab.isPinned {
            dragState.isInSplitMode = true
            dragCoordinator.beginDrag(tabID: tab.id, sourceAreaID: areaID, projectID: projectID)
            dragCoordinator.updatePosition(globalLocation)
            return
        }

        reorderIfNeeded(at: globalLocation)
    }

    private func handleDragEnded(
        tab: TabSnapshot,
        globalLocation: CGPoint,
        dragStartGlobalLocation: CGPoint
    ) {
        if !dragState.didSelect {
            onSelectTab(tab.id)
        }
        if dragState.isInSplitMode {
            if let result = dragCoordinator.endDrag() {
                onDropAction(result)
            }
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            dragState.draggedID = nil
            dragState.isInSplitMode = false
            dragState.frames = [:]
            dragState.lastReorderTargetID = nil
            dragState.didSelect = false
        }
    }

    private func reorderIfNeeded(at location: CGPoint) {
        guard let draggedID = dragState.draggedID else { return }
        var hoveredTargetID: UUID?

        for (id, frame) in dragState.frames where id != draggedID {
            guard frame.contains(location) else { continue }
            hoveredTargetID = id
            guard dragState.lastReorderTargetID != id else { return }

            guard let sourceIndex = tabs.firstIndex(where: { $0.id == draggedID }),
                  let destIndex = tabs.firstIndex(where: { $0.id == id })
            else { return }

            dragState.lastReorderTargetID = id
            let offset = destIndex > sourceIndex ? destIndex + 1 : destIndex
            withAnimation(.easeInOut(duration: 0.15)) {
                onReorderTab(IndexSet(integer: sourceIndex), offset)
            }
            return
        }

        if hoveredTargetID == nil {
            dragState.lastReorderTargetID = nil
        }
    }
}

private typealias TabFramePreferenceKey = UUIDFramePreferenceKey<TabFrameTag>
