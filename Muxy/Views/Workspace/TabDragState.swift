import SwiftUI

struct TabDragState {
    var draggedID: UUID?
    var frames: [UUID: CGRect] = [:]
    var isInSplitMode = false
    var lastReorderTargetID: UUID?
    var didSelect = false
}
