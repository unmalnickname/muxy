enum CloseConfirmationKind {
    case lastTab
    case unsavedEditor
    case runningProcess

    var title: String {
        switch self {
        case .lastTab: "Close Project?"
        case .unsavedEditor: "Save Changes Before Closing?"
        case .runningProcess: "Close Tab?"
        }
    }

    var message: String {
        switch self {
        case .lastTab: "This is the last tab. Closing it will remove the project from the sidebar."
        case .unsavedEditor: "This file has unsaved changes. If you don't save, your changes will be lost."
        case .runningProcess: "A process is still running in this tab. Are you sure you want to close it?"
        }
    }
}
