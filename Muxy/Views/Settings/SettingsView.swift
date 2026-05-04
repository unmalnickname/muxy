import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            EditorSettingsView()
                .tabItem { Label("Editor", systemImage: "pencil.line") }
            KeyboardShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            NotificationSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell") }
            MobileSettingsView()
                .tabItem { Label("Mobile", systemImage: "iphone") }
            AIUsageSettingsView()
                .tabItem { Label("AI Usage", systemImage: "chart.bar") }
            AttentionSettingsView()
                .tabItem { Label("Attention", systemImage: "sparkles") }
        }
        .frame(width: 620, height: 500)
        .resetsSettingsFocusOnOutsideClick()
    }
}
