import Foundation

/// Reads and writes the shared schedule list at
/// `~/Library/Application Support/Tamp/schedules.json`, mirroring `StateStore`.
/// Saving the file doubles as the cross-process signal: the menu bar app
/// watches it, so CLI edits re-arm the running scheduler immediately.
public final class ScheduleStore {
    public let url: URL
    private let coordinator = NSFileCoordinator()

    public init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.url = support.appendingPathComponent("Tamp/schedules.json")
        }
        try? FileManager.default.createDirectory(
            at: self.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    /// Load all schedules, defaulting to none if the file is absent/corrupt.
    public func load() -> [Schedule] {
        var result: [Schedule] = []
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            guard let data = try? Data(contentsOf: readURL),
                  let schedules = try? JSONDecoder.tamp.decode([Schedule].self, from: data)
            else { return }
            result = schedules
        }
        if let coordError {
            kitLog.error("schedules read coordination failed: \(coordError, privacy: .public)")
        }
        return result
    }

    /// Persist the schedule list atomically.
    public func save(_ schedules: [Schedule]) {
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
            do {
                let data = try JSONEncoder.tamp.encode(schedules)
                try data.write(to: writeURL, options: .atomic)
            } catch {
                kitLog.error("schedules save failed: \(String(describing: error), privacy: .public)")
            }
        }
        if let coordError {
            kitLog.error("schedules save coordination failed: \(coordError, privacy: .public)")
        }
    }
}
