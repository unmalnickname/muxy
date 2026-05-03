import AppKit

struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: NSImage
}
