import Foundation

/// The NSFileCoordinator-guarded JSON read/write protocol shared by every
/// on-disk store (state.json, schedules.json), so the coordination, atomic-
/// write, and error-logging semantics live in exactly one place.
///
/// A failed decode returns nil unlogged by design — the stores map it to
/// their default value and the next save rewrites the file. Coordination and
/// write failures are logged: a save that silently didn't land means the file
/// disagrees with reality until the next reconcile.
enum CoordinatedJSONFile {
    static func read<T: Decodable>(
        _ type: T.Type, at url: URL, coordinator: NSFileCoordinator, label: String
    ) -> T? {
        var result: T?
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            guard let data = try? Data(contentsOf: readURL),
                  let value = try? JSONDecoder.tamp.decode(type, from: data)
            else { return }
            result = value
        }
        if let coordError {
            kitLog.error("\(label, privacy: .public) read coordination failed: \(coordError, privacy: .public)")
        }
        return result
    }

    static func write<T: Encodable>(
        _ value: T, at url: URL, coordinator: NSFileCoordinator, label: String
    ) {
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
            do {
                let data = try JSONEncoder.tamp.encode(value)
                try data.write(to: writeURL, options: .atomic)
            } catch {
                kitLog.error("\(label, privacy: .public) save failed: \(String(describing: error), privacy: .public)")
            }
        }
        if let coordError {
            kitLog.error("\(label, privacy: .public) save coordination failed: \(coordError, privacy: .public)")
        }
    }

    /// Default location for a Tamp data file, next to its siblings.
    static func defaultURL(filename: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tamp/\(filename)")
    }
}

/// Reads and writes the shared state file at
/// `~/Library/Application Support/Tamp/state.json`, so the menu bar app and
/// the CLI agree on the current caffeination state.
public final class StateStore {
    public let url: URL
    private let coordinator = NSFileCoordinator()

    public init(url: URL? = nil) {
        self.url = url ?? CoordinatedJSONFile.defaultURL(filename: "state.json")
        try? FileManager.default.createDirectory(
            at: self.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    /// Load the raw persisted state, defaulting to inactive if absent/corrupt.
    public func loadRaw() -> TampState {
        CoordinatedJSONFile.read(TampState.self, at: url, coordinator: coordinator, label: "state")
            ?? .inactive()
    }

    /// Persist the given state atomically. A failed save is serious — the
    /// tracked caffeinate may already be gone/killed while the file still says
    /// active — though status() self-heals on the next read.
    public func save(_ state: TampState) {
        CoordinatedJSONFile.write(state, at: url, coordinator: coordinator, label: "state")
    }
}

extension JSONEncoder {
    public static var tamp: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    public static var tamp: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
