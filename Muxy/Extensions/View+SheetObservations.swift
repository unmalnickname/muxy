import SwiftUI

extension View {
    func sheetObservations(
        toggleAttachedVCSPanel: @escaping () -> Void,
        toggleFileTreePanel: @escaping () -> Void,
        toggleHealthPanel: @escaping () -> Void,
        togglePipelinePanel: @escaping () -> Void
    ) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: .toggleAttachedVCS)) { _ in
                toggleAttachedVCSPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleFileTree)) { _ in
                toggleFileTreePanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleHealth)) { _ in
                toggleHealthPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .togglePipeline)) { _ in
                togglePipelinePanel()
            }
    }
}
