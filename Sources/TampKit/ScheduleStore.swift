import Foundation

/// Reads and writes the shared schedule list at
/// `~/Library/Application Support/Tamp/schedules.json`. Saving the file
/// doubles as the cross-process signal: the menu bar app watches it, so CLI
/// edits re-arm the running scheduler immediately.
public final class ScheduleStore {
    public let url: URL
    private let coordinator = NSFileCoordinator()

    public init(url: URL? = nil) {
        self.url = url ?? CoordinatedJSONFile.defaultURL(filename: "schedules.json")
        try? FileManager.default.createDirectory(
            at: self.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    /// Load all schedules, defaulting to none if the file is absent/corrupt.
    public func load() -> [Schedule] {
        CoordinatedJSONFile.read([Schedule].self, at: url, coordinator: coordinator, label: "schedules")
            ?? []
    }

    /// Persist the schedule list atomically.
    public func save(_ schedules: [Schedule]) {
        CoordinatedJSONFile.write(schedules, at: url, coordinator: coordinator, label: "schedules")
    }
}
