import SwiftUI

struct SidebarFooter: View {
    var expanded: Bool = false
    @AppStorage(AIUsageSettingsStore.usageEnabledKey) private var usageEnabled = false
    @AppStorage(AIUsageSettingsStore.usageDisplayModeKey) private var usageDisplayModeRaw = AIUsageSettingsStore.defaultUsageDisplayMode
        .rawValue
    @AppStorage(AIUsageSettingsStore.sidebarPreviewProviderIDKey) private var pinnedPreviewProviderID: String = ""
    @State private var showThemePicker = false
    @State private var showNotifications = false
    @State private var showAIUsagePopover = false
    @State private var testGlowIndex = 0
    private let usageService = AIUsageService.shared
    @Environment(AttentionState.self) private var attentionState

    private var usageDisplayMode: AIUsageDisplayMode {
        AIUsageDisplayMode(rawValue: usageDisplayModeRaw) ?? AIUsageSettingsStore.defaultUsageDisplayMode
    }

    private let usageRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var notificationStore: NotificationStore { NotificationStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            if expanded {
                expandedFooter
            } else {
                collapsedFooter
            }
        }
        .task {
            await usageService.refreshIfNeeded()
        }
        .onReceive(usageRefreshTimer) { _ in
            Task {
                await usageService.refreshIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleThemePicker)) { _ in
            showThemePicker.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleNotificationPanel)) { _ in
            showNotifications.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleAIUsage)) { _ in
            guard usageEnabled else { return }
            showAIUsagePopover.toggle()
        }
        .onChange(of: usageEnabled) { _, enabled in
            if !enabled {
                showAIUsagePopover = false
            }
        }
        .onChange(of: attentionState.agentCompletionDate) { _, newDate in
            if newDate == nil, testGlowIndex == 1 {
                testGlowIndex = 0
            }
        }
    }

    private func postToggleSidebar() {
        NotificationCenter.default.post(name: .toggleSidebar, object: nil)
    }

    private var sidebarToggleLabel: String {
        expanded ? "Collapse Sidebar" : "Expand Sidebar"
    }

    private var sidebarToggleIcon: String {
        "sidebar.left"
    }

    private var notificationBellIcon: String {
        notificationStore.unreadCount > 0 ? "bell.badge" : "bell"
    }

    private var previewProviderDisplay: (percent: Int, iconName: String)? {
        guard let selection = usageService.previewSelection(pinnedRawValue: pinnedPreviewProviderID),
              case .available = selection.snapshot.state
        else { return nil }

        let snapshot = selection.snapshot
        let rowPercent = selection.row?.percent
        let usedPercent = max(0, min(100, rowPercent ?? snapshot.rows.compactMap(\.percent).max() ?? 0))
        let displayPercent: Double = switch usageDisplayMode {
        case .used:
            usedPercent
        case .remaining:
            max(0, min(100, 100 - usedPercent))
        }

        return (Int(displayPercent.rounded()), snapshot.providerIconName)
    }

    private var previewProviderPercentLabel: String? {
        guard let display = previewProviderDisplay else { return nil }
        return "\(max(0, min(100, display.percent)))%"
    }

    private var aiUsageButton: some View {
        AIUsagePreviewButton(
            display: previewProviderDisplay,
            percentLabel: previewProviderPercentLabel,
            expanded: expanded,
            onTap: { showAIUsagePopover.toggle() }
        )
        .popover(isPresented: $showAIUsagePopover) {
            AIUsagePanel(
                snapshots: usageService.snapshots,
                isRefreshing: usageService.isRefreshing,
                lastRefreshDate: usageService.lastRefreshDate,
                onRefresh: refreshUsage
            )
        }
        .help("AI Usage (\(KeyBindingStore.shared.combo(for: .toggleAIUsage).displayString))")
    }

    private var collapsedFooter: some View {
        VStack(spacing: 4) {
            if usageEnabled {
                aiUsageButton
            }
            IconButton(symbol: notificationBellIcon, accessibilityLabel: "Notifications") { showNotifications.toggle() }
                .help("Notifications")
                .popover(isPresented: $showNotifications) {
                    NotificationPanel(onDismiss: { showNotifications = false })
                }
            IconButton(symbol: "paintpalette", accessibilityLabel: "Theme Picker") { showThemePicker.toggle() }
                .help("Theme Picker (\(KeyBindingStore.shared.combo(for: .toggleThemePicker).displayString))")
                .popover(isPresented: $showThemePicker) { ThemePicker() }
            testGlowButton
            IconButton(symbol: sidebarToggleIcon, accessibilityLabel: sidebarToggleLabel) { postToggleSidebar() }
                .help("\(sidebarToggleLabel) (\(KeyBindingStore.shared.combo(for: .toggleSidebar).displayString))")
        }
        .padding(.bottom, 8)
    }

    private var expandedFooter: some View {
        HStack(spacing: 4) {
            IconButton(symbol: sidebarToggleIcon, accessibilityLabel: sidebarToggleLabel) { postToggleSidebar() }
                .help("\(sidebarToggleLabel) (\(KeyBindingStore.shared.combo(for: .toggleSidebar).displayString))")

            Spacer()

            if usageEnabled {
                aiUsageButton
            }
            IconButton(symbol: notificationBellIcon, accessibilityLabel: "Notifications") { showNotifications.toggle() }
                .help("Notifications")
                .popover(isPresented: $showNotifications) {
                    NotificationPanel(onDismiss: { showNotifications = false })
                }
            IconButton(symbol: "paintpalette", accessibilityLabel: "Theme Picker") { showThemePicker.toggle() }
                .help("Theme Picker (\(KeyBindingStore.shared.combo(for: .toggleThemePicker).displayString))")
                .popover(isPresented: $showThemePicker) { ThemePicker() }
            testGlowButton
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var testGlowButton: some View {
        let icon = switch testGlowIndex {
        case 1: "sparkles"
        case 2: "moon.stars"
        default: "sparkles"
        }
        let tint = switch testGlowIndex {
        case 1: Color(red: 0, green: 0.8, blue: 0.8)
        case 2: Color.orange
        default: MuxyTheme.fgMuted
        }
        return IconButton(symbol: icon, color: testGlowIndex == 0 ? MuxyTheme.fgMuted : tint, accessibilityLabel: "Test Glow") {
            cycleTestGlow()
        }
        .help("Test Glow")
    }

    private func cycleTestGlow() {
        switch testGlowIndex {
        case 0:
            testGlowIndex = 1
            attentionState.agentCompleted()
        case 1:
            testGlowIndex = 2
            attentionState.setIdle(true)
        case 2:
            testGlowIndex = 0
            attentionState.setIdle(false)
        default:
            testGlowIndex = 0
        }
    }

    private func refreshUsage() {
        Task {
            await usageService.refresh(force: true)
        }
    }
}
