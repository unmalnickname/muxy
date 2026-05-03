import SwiftUI

struct WindowOpenReceiver: View {
    let openWindow: OpenWindowAction

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .openVCSWindow)) { _ in
                openWindow(id: "vcs")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openHelpWindow)) { _ in
                openWindow(id: "help")
            }
    }
}
