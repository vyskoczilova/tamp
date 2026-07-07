import Foundation

/// Which kinds of sleep are being prevented. Mirrors `caffeinate` flags.
public struct SleepFlags: Codable, Equatable, Sendable {
    /// `-d` — prevent the display from sleeping.
    public var display: Bool
    /// `-i` — prevent the system from idle sleeping.
    public var system: Bool
    /// `-m` — prevent the disk from idle sleeping.
    public var disk: Bool
    /// `-s` — prevent system sleep, effective only while on AC power.
    public var acPower: Bool
    /// `-u` — declare user activity, waking the display. caffeinate holds this
    /// assertion for the whole session only when the session is timed (`-t`);
    /// otherwise macOS drops it after a few seconds.
    public var wake: Bool

    public init(
        display: Bool = true,
        system: Bool = true,
        disk: Bool = false,
        acPower: Bool = false,
        wake: Bool = false
    ) {
        self.display = display
        self.system = system
        self.disk = disk
        self.acPower = acPower
        self.wake = wake
    }

    private enum CodingKeys: String, CodingKey {
        case display, system, disk, acPower, wake
    }

    /// State files written before 1.1.0 lack the newer keys, so every field
    /// falls back to its default instead of failing the whole decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        display = try container.decodeIfPresent(Bool.self, forKey: .display) ?? true
        system = try container.decodeIfPresent(Bool.self, forKey: .system) ?? true
        disk = try container.decodeIfPresent(Bool.self, forKey: .disk) ?? false
        acPower = try container.decodeIfPresent(Bool.self, forKey: .acPower) ?? false
        wake = try container.decodeIfPresent(Bool.self, forKey: .wake) ?? false
    }

    /// The `caffeinate` flag arguments these settings map to.
    public var caffeinateArguments: [String] {
        var args: [String] = []
        if display { args.append("-d") }
        if system { args.append("-i") }
        if disk { args.append("-m") }
        if acPower { args.append("-s") }
        if wake { args.append("-u") }
        return args
    }

    /// The individual sleep types with display labels and a short description —
    /// the single source for UIs that present a per-type toggle (e.g. the
    /// settings panel's "Keep Awake").
    public static var toggles: [(label: String, detail: String, keyPath: WritableKeyPath<SleepFlags, Bool>)] {
        [
            ("Display", "Keep the screen awake", \.display),
            ("System", "Keep the Mac awake, even when idle", \.system),
            ("Disk", "Keep disks from spinning down", \.disk),
            ("AC Power", "Keep the Mac awake while plugged in (no effect on battery)", \.acPower),
            ("Wake Display", "Wake the display when a session starts", \.wake),
        ]
    }
}

/// The persisted, shared source of truth for the menu bar app and the CLI.
public struct TampState: Codable, Equatable, Sendable {
    public var active: Bool
    /// PID of the running `caffeinate` process, if any.
    public var pid: Int32?
    /// When a timed session ends. Nil for indefinite sessions.
    public var endsAt: Date?
    public var flags: SleepFlags

    public init(
        active: Bool = false,
        pid: Int32? = nil,
        endsAt: Date? = nil,
        flags: SleepFlags = SleepFlags()
    ) {
        self.active = active
        self.pid = pid
        self.endsAt = endsAt
        self.flags = flags
    }

    /// The inactive state, preserving the desired sleep flags.
    public static func inactive(flags: SleepFlags = SleepFlags()) -> TampState {
        TampState(active: false, flags: flags)
    }

    /// Seconds remaining for a timed session, or nil if indefinite/inactive.
    public func remaining(now: Date = Date()) -> TimeInterval? {
        guard active, let endsAt else { return nil }
        return max(0, endsAt.timeIntervalSince(now))
    }

    /// A coarse classification of the session for display. Both front-ends map
    /// this to their own wording, so the off/timed/indefinite logic — and any
    /// future state — lives (and stays in sync) in one place.
    public enum Phase: Sendable, Equatable {
        case off
        case onIndefinite
        case onTimed(remaining: TimeInterval)
        /// The Mac is caffeinated by an external process (not Tamp's own session).
        case externallyActive
    }

    /// Pass `systemActive: SystemAssertions.isCaffeinated()` to get a phase
    /// that reflects the real OS state, including external caffeinate processes.
    public func phase(systemActive: Bool = false, now: Date = Date()) -> Phase {
        guard active else {
            return systemActive ? .externallyActive : .off
        }
        if let remaining = remaining(now: now) { return .onTimed(remaining: remaining) }
        return .onIndefinite
    }
}

/// Machine-readable status snapshot for scripting (`status --json`). Wraps the
/// raw state with the resolved phase so consumers see external caffeination
/// too, without reimplementing the phase logic.
public struct StatusReport: Codable, Equatable, Sendable {
    public let state: TampState
    /// One of "off", "onIndefinite", "onTimed", "externallyActive".
    public let phase: String
    /// Whole seconds left in a timed session, nil otherwise.
    public let remainingSeconds: Int?

    public init(state: TampState, systemActive: Bool, now: Date = Date()) {
        self.state = state
        switch state.phase(systemActive: systemActive, now: now) {
        case .off:
            phase = "off"
            remainingSeconds = nil
        case .onIndefinite:
            phase = "onIndefinite"
            remainingSeconds = nil
        case .onTimed(let remaining):
            phase = "onTimed"
            remainingSeconds = Int(remaining.rounded())
        case .externallyActive:
            phase = "externallyActive"
            remainingSeconds = nil
        }
    }
}
