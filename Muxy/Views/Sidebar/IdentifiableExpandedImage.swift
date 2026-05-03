import AppKit

struct IdentifiableExpandedImage: Identifiable {
    let id = UUID()
    let image: NSImage
}
