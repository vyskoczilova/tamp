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
    public func loadRaw() -> CoffeeState {
        var result = CoffeeState.inactive()
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            guard let data = try? Data(contentsOf: readURL),
                  let state = try? JSONDecoder.coffee.decode(CoffeeState.self, from: data)
            else { return }
            result = state
        }
        return result
    }

    /// Persist the given state atomically.
    public func save(_ state: CoffeeState) {
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
            guard let data = try? JSONEncoder.coffee.encode(state) else { return }
            try? data.write(to: writeURL, options: .atomic)
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
