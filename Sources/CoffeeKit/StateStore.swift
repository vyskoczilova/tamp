import Foundation

/// Reads and writes the shared state file at
/// `~/Library/Application Support/Coffee/state.json`, so the menu bar app and
/// the CLI agree on the current caffeination state.
public final class StateStore {
    public let url: URL
    private let coordinator = NSFileCoordinator()

    public init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.url = support.appendingPathComponent("Coffee/state.json")
        }
        try? FileManager.default.createDirectory(
            at: self.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    /// Load the raw persisted state, defaulting to inactive if absent/corrupt.
    /// (An unreadable file mapping to "inactive" is by design — the next save
    /// rewrites it — so decode failures are not logged.)
    public func loadRaw() -> CoffeeState {
        var result = CoffeeState.inactive()
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            guard let data = try? Data(contentsOf: readURL),
                  let state = try? JSONDecoder.coffee.decode(CoffeeState.self, from: data)
            else { return }
            result = state
        }
        if let coordError {
            kitLog.error("state read coordination failed: \(coordError, privacy: .public)")
        }
        return result
    }

    /// Persist the given state atomically. A failed save is serious — the
    /// tracked caffeinate may already be gone/killed while the file still says
    /// active — so it is logged, though status() self-heals on the next read.
    public func save(_ state: CoffeeState) {
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
            do {
                let data = try JSONEncoder.coffee.encode(state)
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
    public static var coffee: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    public static var coffee: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
