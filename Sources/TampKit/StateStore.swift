import Foundation

/// Reads and writes the shared state file at
/// `~/Library/Application Support/Tamp/state.json`, so the menu bar app and
/// the CLI agree on the current caffeination state.
public final class StateStore {
    public let url: URL
    private let coordinator = NSFileCoordinator()

    public init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.url = support.appendingPathComponent("Tamp/state.json")
        }
        try? FileManager.default.createDirectory(
            at: self.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    /// Load the raw persisted state, defaulting to inactive if absent/corrupt.
    /// (An unreadable file mapping to "inactive" is by design — the next save
    /// rewrites it — so decode failures are not logged.)
    public func loadRaw() -> TampState {
        var result = TampState.inactive()
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            guard let data = try? Data(contentsOf: readURL),
                  let state = try? JSONDecoder.tamp.decode(TampState.self, from: data)
            else { return }
            result = state
        }
        if let coordError {
            kitLog.error("state read coordination failed: \(coordError, privacy: .public)")
        }
        return result
    }

    /// Coordinated read-modify-write: load the current state, apply `transform`,
    /// and persist the result as ONE coordinated block. `NSFileCoordinator`
    /// write coordination is real cross-process mutual exclusion (all Tamp
    /// processes go through this store), so concurrent `hold`/`release` calls
    /// from different processes serialize instead of dropping updates — this is
    /// the primitive that makes refcounted holds safe. Side effects that must
    /// be decided atomically with the state (spawning/killing caffeinate)
    /// belong inside `transform`.
    @discardableResult
    public func mutate(_ transform: (inout TampState) -> Void) -> TampState {
        var result = TampState.inactive()
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
            var state = TampState.inactive()
            if let data = try? Data(contentsOf: writeURL),
               let decoded = try? JSONDecoder.tamp.decode(TampState.self, from: data) {
                state = decoded
            }
            transform(&state)
            do {
                let data = try JSONEncoder.tamp.encode(state)
                try data.write(to: writeURL, options: .atomic)
            } catch {
                kitLog.error("state mutate save failed: \(String(describing: error), privacy: .public)")
            }
            result = state
        }
        if let coordError {
            kitLog.error("state mutate coordination failed: \(coordError, privacy: .public)")
        }
        return result
    }

    /// Persist the given state atomically. A failed save is serious — the
    /// tracked caffeinate may already be gone/killed while the file still says
    /// active — so it is logged, though status() self-heals on the next read.
    public func save(_ state: TampState) {
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
            do {
                let data = try JSONEncoder.tamp.encode(state)
                try data.write(to: writeURL, options: .atomic)
            } catch {
                kitLog.error("state save failed: \(String(describing: error), privacy: .public)")
            }
        }
        if let coordError {
            kitLog.error("state save coordination failed: \(coordError, privacy: .public)")
        }
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
