import Foundation

/// The engine. Wraps `/usr/bin/caffeinate`, owns the shared state, and keeps it
/// reconciled with reality (a recorded PID that no longer exists means inactive).
///
/// Two independent things can want the Mac awake: the single manual session
/// (`on`/`for`/`until`) and any number of named holds (`hold`/`release`). Both
/// share one tracked caffeinate process; it runs while
/// `TampState.keepsAwake` holds. All decisions that depend on current state
/// (am I the first hold? the last release?) happen inside `StateStore.mutate`,
/// so concurrent callers from different processes serialize safely.
public final class CaffeinateController {
    public static let caffeinatePath = "/usr/bin/caffeinate"

    private let store: StateStore
    private let preferences: Preferences

    public init(store: StateStore = StateStore(), preferences: Preferences = Preferences()) {
        self.store = store
        self.preferences = preferences
    }

    /// Current state, reconciled against the running process. Read-only unless
    /// something actually drifted (dead PID, expired hold) — the common path is
    /// a single coordinated read plus one process-name check.
    public func status() -> TampState {
        let state = store.loadRaw()
        guard needsSettle(state) else { return state }
        return store.mutate { state in
            do { try self.settle(&state) } catch {
                kitLog.error("status settle failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Start a manual session. `duration` nil means indefinite; otherwise timed.
    /// `flags` overrides the saved preferences for this session when provided.
    /// Holds are preserved — a manual session layers on top of them.
    @discardableResult
    public func start(duration seconds: Int? = nil, flags: SleepFlags? = nil) throws -> TampState {
        let effectiveFlags = flags ?? preferences.sleepFlags
        return try mutateState { state in
            // Replace any existing tracked process (manual or holder-spawned)
            // so the new flags/duration take effect.
            self.killTracked(&state)
            state.pid = try self.spawnCaffeinate(flags: effectiveFlags, seconds: seconds)
            state.active = true
            state.endsAt = seconds.map { Date().addingTimeInterval(TimeInterval($0)) }
            state.flags = effectiveFlags
        }
    }

    /// Register a named hold. Starts caffeinate if nothing is running yet;
    /// otherwise just records the id. Re-holding the same id is a refresh
    /// (idempotent; updates the TTL), so refcounting is by name, not a counter
    /// a double-firing hook could inflate. `ttl` seconds, when given, make the
    /// hold self-expire so a crashed caller can't pin the Mac awake forever.
    @discardableResult
    public func hold(_ id: String, ttl seconds: Int? = nil) throws -> TampState {
        try mutateState { state in
            let now = Date()
            state.holders.removeAll { $0.id == id }
            state.holders.append(TampState.Holder(
                id: id,
                expiresAt: seconds.map { now.addingTimeInterval(TimeInterval($0)) }
            ))
            try self.settle(&state, now: now)
        }
    }

    /// Remove a named hold. Stops caffeinate only if this was the last hold
    /// and no manual session is active. Releasing an unknown id is a no-op
    /// (idempotent), so double-firing hooks are harmless.
    @discardableResult
    public func release(_ id: String) throws -> TampState {
        try mutateState { state in
            state.holders.removeAll { $0.id == id }
            try self.settle(&state)
        }
    }

    /// Drop every hold — the escape hatch for a caller that died without
    /// releasing. A manual session, if any, keeps running.
    @discardableResult
    public func releaseAll() -> TampState {
        store.mutate { state in
            state.holders.removeAll()
            // No spawn can happen with zero holders, so settle cannot throw here.
            try? self.settle(&state)
        }
    }

    /// Persist new sleep preferences. If anything is live (manual session or
    /// holds), bounce the tracked process so the flags take effect immediately
    /// while preserving the session shape — remaining time and holds included.
    @discardableResult
    public func applyFlags(_ flags: SleepFlags) throws -> TampState {
        preferences.sleepFlags = flags
        return try mutateState { state in
            try self.settle(&state) // reconcile first (prunes, self-heals)
            guard state.keepsAwake() else { return }
            self.killTracked(&state)
            if state.active {
                state.pid = try self.spawnCaffeinate(
                    flags: flags,
                    seconds: state.remaining().map { Int($0) }
                )
                state.flags = flags
            } else {
                try self.settle(&state) // holder respawn picks up the new prefs
            }
        }
    }

    /// Stop everything — the manual session AND all holds. An explicit user
    /// "off" wins over background holders; hook-based holders re-register on
    /// their next natural trigger. Safe to call when already inactive.
    @discardableResult
    public func stop() -> TampState {
        store.mutate { state in
            self.killTracked(&state)
            state = TampState.inactive(flags: state.flags)
        }
    }

    /// Toggle: anything keeping the Mac awake through Tamp (manual session or
    /// holds) → stop it all; otherwise start an indefinite manual session.
    @discardableResult
    public func toggle() throws -> TampState {
        if status().keepsAwake() {
            return stop()
        }
        return try start()
    }

    // MARK: - Reconciliation

    /// Bring the persisted state and the real process into agreement. MUST run
    /// inside a `StateStore.mutate` block — that is what makes first-hold /
    /// last-release decisions race-free across processes. Handles, in order:
    /// expired holds pruned; a dead manual session cleared (timer elapsed,
    /// manual kill, recycled PID); a missing process respawned while holds
    /// remain (also how holds survive a timed session's `-t` expiry); a
    /// process nothing wants anymore killed.
    /// Paired with `needsSettle` — a new drift condition here needs a matching
    /// check there, or `status()` stops self-healing for that case.
    private func settle(_ state: inout TampState, now: Date = Date()) throws {
        state.holders.removeAll { $0.isExpired(now: now) }
        let pidLive = state.pid.map(isTrackedCaffeinate) == true
        if state.active && !pidLive {
            state.active = false
            state.endsAt = nil
            state.pid = nil
        }
        if state.keepsAwake(now: now) {
            guard !pidLive else { return }
            // Only holds can reach here (a dead manual session was cleared
            // above): spawn indefinite, with the currently preferred flags.
            state.flags = preferences.sleepFlags
            state.pid = try spawnCaffeinate(flags: state.flags)
            state.endsAt = nil
        } else {
            killTracked(&state)
            state.endsAt = nil
        }
    }

    /// Cheap pre-check so `status()` only takes write coordination when the
    /// state actually drifted from reality. Mirrors `settle`'s conditions.
    private func needsSettle(_ state: TampState, now: Date = Date()) -> Bool {
        if state.holders.contains(where: { $0.isExpired(now: now) }) { return true }
        let pidLive = state.pid.map(isTrackedCaffeinate) == true
        let wantsRun = state.keepsAwake(now: now)
        if wantsRun != pidLive { return true }
        if !wantsRun && state.pid != nil { return true }
        return false
    }

    // MARK: - Process management

    /// `StateStore.mutate` with a throwing body — the spawn side effect can
    /// throw, and the error must escape the non-throwing coordination closure.
    @discardableResult
    private func mutateState(_ body: (inout TampState) throws -> Void) throws -> TampState {
        var thrown: Error?
        let state = store.mutate { state in
            do { try body(&state) } catch { thrown = error }
        }
        if let thrown { throw thrown }
        return state
    }

    /// Spawn a detached caffeinate and return its PID. Indefinite when
    /// `seconds` is nil.
    private func spawnCaffeinate(flags: SleepFlags, seconds: Int? = nil) throws -> Int32 {
        var args = flags.caffeinateArguments
        if args.isEmpty { args.append("-i") } // Never launch a no-op caffeinate.
        if let seconds { args.append(contentsOf: ["-t", String(seconds)]) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.caffeinatePath)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process.processIdentifier
    }

    /// Kill the tracked process — after verifying it still names a caffeinate —
    /// and forget it. The single home of the "never trust a recorded PID"
    /// kill rule.
    private func killTracked(_ state: inout TampState) {
        if let pid = state.pid, isTrackedCaffeinate(pid) {
            kill(pid, SIGTERM)
        }
        state.pid = nil
    }

    /// PIDs are recycled (reboot, timer expiry), so a recorded PID must never be
    /// trusted — let alone killed — unless the process behind it is still a
    /// caffeinate.
    private func isTrackedCaffeinate(_ pid: Int32) -> Bool {
        SystemAssertions.processName(of: pid) == "caffeinate"
    }
}
