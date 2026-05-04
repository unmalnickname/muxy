import Foundation

final class DirectoryWatcher: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject
    private let fd: Int32

    init?(path: String, handler: @escaping @Sendable () -> Void) {
        let filePath = (path as NSString).fileSystemRepresentation
        guard path != "/" else { return nil }
        let fd = open(filePath, O_EVTONLY)
        guard fd >= 0 else { return nil }
        self.fd = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue(label: "app.muxy.dir-watch.\(path.hash)", qos: .utility)
        )

        source.setEventHandler { handler() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    deinit {
        source.cancel()
    }
}

