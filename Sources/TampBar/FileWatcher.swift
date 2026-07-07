import Foundation

/// Watches one file and calls back on every change, re-arming after each
/// event because the stores write atomically (each save replaces the inode).
/// Events are delivered on the main queue. Instances are meant to live for
/// the app's lifetime; call `cancel()` if one must be discarded early.
@MainActor
final class FileWatcher {
    private let path: String
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
        arm()
    }

    func cancel() {
        source?.cancel()
        source = nil
    }

    private func arm() {
        // Self-heal a deleted file (the old inline watcher did this on every
        // re-arm): without it a .delete event would leave the watcher dead
        // for the app's lifetime. An empty file reads as "no data" in both
        // stores, and the next save overwrites it.
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            // Delivered on the main queue, so it is safe to assume isolation.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.source?.cancel()
                self.arm()
                self.onChange()
            }
        }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }
}
