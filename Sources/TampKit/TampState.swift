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
public struct TampState: Codable, Equatable, Sendable {
    public var active: Bool
    /// PID of the running `caffeinate` process, if any.
    public var pid: Int32?
    /// When a timed session ends. Nil for indefinite sessions.
    public var endsAt: Date?
    public var flags: SleepFlags
    /// Named refcounted holds (`tamp hold <id>`), orthogonal to the manual
    /// session: caffeinate should run while `active || !holders.isEmpty`.
    public var holders: [Holder]

    /// One named hold. Registered by external callers (scripts, hooks) that
    /// want keep-awake without racing each other over a single on/off switch.
    public struct Holder: Codable, Equatable, Sendable {
        public var id: String
        /// Optional self-destruct so a crashed caller can't pin the Mac awake
        /// forever. Nil means the hold lives until explicitly released.
        public var expiresAt: Date?

        public init(id: String, expiresAt: Date? = nil) {
            self.id = id
            self.expiresAt = expiresAt
        }

        public func isExpired(now: Date = Date()) -> Bool {
            guard let expiresAt else { return false }
            return expiresAt <= now
        }

        /// Shared "2 holds active" wording so the CLI and menu bar can't drift.
        public static func countLabel(_ count: Int) -> String {
            "\(count) hold\(count == 1 ? "" : "s") active"
        }
    }

    public init(
        active: Bool = false,
        pid: Int32? = nil,
        endsAt: Date? = nil,
        flags: SleepFlags = SleepFlags(),
        holders: [Holder] = []
    ) {
        self.active = active
        self.pid = pid
        self.endsAt = endsAt
        self.flags = flags
        self.holders = holders
    }

    private enum CodingKeys: String, CodingKey {
        case active, pid, endsAt, flags, holders
    }

    /// Custom decode only to default `holders` — state files written before
    /// the field existed must keep loading.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        active = try container.decode(Bool.self, forKey: .active)
        pid = try container.decodeIfPresent(Int32.self, forKey: .pid)
        endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
        flags = try container.decode(SleepFlags.self, forKey: .flags)
        holders = try container.decodeIfPresent([Holder].self, forKey: .holders) ?? []
    }

    /// The inactive state, preserving the desired sleep flags. Also drops all
    /// holders — this is what a manual "off" means: the user wins, holders
    /// re-register on their next natural trigger.
    public static func inactive(flags: SleepFlags = SleepFlags()) -> TampState {
        TampState(active: false, flags: flags)
    }

    /// Holders that have not expired yet.
    public func liveHolders(now: Date = Date()) -> [Holder] {
        holders.filter { !$0.isExpired(now: now) }
    }

    /// Whether Tamp itself wants caffeinate running — a manual session or at
    /// least one live hold. This is THE definition of "on/stoppable": the
    /// engine's settle logic and both front-ends consult it rather than
    /// re-deriving it, so a future keep-awake source is added in one place.
    public func keepsAwake(now: Date = Date()) -> Bool {
        active || !liveHolders(now: now).isEmpty
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
        /// Kept awake only by registered holds (`tamp hold`), no manual session.
        case heldBy(count: Int)
        /// The Mac is caffeinated by an external process (not Tamp's own session).
        case externallyActive
    }

    /// Pass `systemActive: SystemAssertions.isCaffeinated()` to get a phase
    /// that reflects the real OS state, including external caffeinate processes.
    /// A manual session outranks holds for display; holds outrank external.
    /// `systemActive` is an autoclosure so the (expensive, full process-table)
    /// external scan only runs when Tamp itself isn't keeping the Mac awake.
    public func phase(systemActive: @autoclosure () -> Bool = false, now: Date = Date()) -> Phase {
        if active {
            if let remaining = remaining(now: now) { return .onTimed(remaining: remaining) }
            return .onIndefinite
        }
        let held = liveHolders(now: now).count
        if held > 0 { return .heldBy(count: held) }
        return systemActive() ? .externallyActive : .off
    }
}

/// Machine-readable status snapshot for scripting (`status --json`). Wraps the
/// raw state with the resolved phase so consumers see external caffeination
/// too, without reimplementing the phase logic.
public struct StatusReport: Codable, Equatable, Sendable {
    public let state: TampState
    /// One of "off", "onIndefinite", "onTimed", "heldBy", "externallyActive".
    public let phase: String
    /// Whole seconds left in a timed session, nil otherwise.
    public let remainingSeconds: Int?
    /// IDs of live (non-expired) holds.
    public let holders: [String]

    public init(state: TampState, systemActive: Bool, now: Date = Date()) {
        self.state = state
        self.holders = state.liveHolders(now: now).map(\.id)
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
        case .heldBy:
            phase = "heldBy"
            remainingSeconds = nil
        case .externallyActive:
            phase = "externallyActive"
            remainingSeconds = nil
        }
    }
}
