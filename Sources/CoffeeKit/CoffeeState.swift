import Foundation

/// Which kinds of sleep are being prevented. Mirrors `caffeinate` flags.
public struct SleepFlags: Codable, Equatable, Sendable {
    /// `-d` — prevent the display from sleeping.
    public var display: Bool
    /// `-i` — prevent the system from idle sleeping.
    public var system: Bool
    /// `-m` — prevent the disk from idle sleeping.
    public var disk: Bool

    public init(display: Bool = true, system: Bool = true, disk: Bool = false) {
        self.display = display
        self.system = system
        self.disk = disk
    }

    /// The `caffeinate` flag arguments these settings map to.
    public var caffeinateArguments: [String] {
        var args: [String] = []
        if display { args.append("-d") }
        if system { args.append("-i") }
        if disk { args.append("-m") }
        return args
    }

    /// The individual sleep types with display labels and a short description —
    /// the single source for UIs that present a per-type toggle (e.g. the
    /// settings panel's "Prevent Sleep Of").
    public static var toggles: [(label: String, detail: String, keyPath: WritableKeyPath<SleepFlags, Bool>)] {
        [
            ("Display", "Keep the screen awake", \.display),
            ("System", "Keep the Mac awake, even when idle", \.system),
            ("Disk", "Keep disks from spinning down", \.disk),
        ]
    }
}

/// The persisted, shared source of truth for the menu bar app and the CLI.
public struct CoffeeState: Codable, Equatable, Sendable {
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
    public static func inactive(flags: SleepFlags = SleepFlags()) -> CoffeeState {
        CoffeeState(active: false, flags: flags)
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
        /// The Mac is caffeinated by an external process (not Coffee's own session).
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
    public let state: CoffeeState
    /// One of "off", "onIndefinite", "onTimed", "externallyActive".
    public let phase: String
    /// Whole seconds left in a timed session, nil otherwise.
    public let remainingSeconds: Int?

    public init(state: CoffeeState, systemActive: Bool, now: Date = Date()) {
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
