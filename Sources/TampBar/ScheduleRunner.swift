import AppKit
import TampKit

/// Runs recurring schedules while the app is alive (there is no daemon — the
/// menu bar app *is* the scheduler). A one-shot timer is armed at the next
/// window transition; at a window start the runner launches a plain timed
/// session ending at the window end, so all the existing machinery (endsAt
/// display, reconcile, extend, end-of-session notification) applies untouched
/// and the session is indistinguishable from `tamp until 17:00`.
///
/// Firing is edge-triggered per window (`firedWindowStart`): turning
/// keep-awake off mid-window keeps it off for the rest of that window. A
/// fresh app launch mid-window *does* catch up and fire once — schedules
/// survive reboots that way. Re-evaluation happens on launch, timer fire,
/// wake from sleep, and every schedules-file change (CLI edits included).
@MainActor
final class ScheduleRunner: NSObject {
    private let controller: CaffeinateController
    private let store: ScheduleStore
    private let onChange: () -> Void
    private var watcher: FileWatcher?
    private var timer: Timer?
    private var firedWindowStart: Date?

    init(controller: CaffeinateController, store: ScheduleStore, onChange: @escaping () -> Void) {
        self.controller = controller
        self.store = store
        self.onChange = onChange
        super.init()
        // Ensure the file exists so the watcher has an inode to attach to.
        if !FileManager.default.fileExists(atPath: store.url.path) {
            store.save([])
        }
        watcher = FileWatcher(path: store.url.path) { [weak self] in self?.evaluate() }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        evaluate()
    }

    /// Re-read the schedules, act on the window containing now, and re-arm
    /// the timer for the next transition. The firing policy itself is pure
    /// TampKit logic (`Scheduler.firingDecision`); this only executes it.
    func evaluate() {
        let schedules = store.load()
        let now = Date()
        defer { rearm(schedules: schedules, now: now) }

        switch Scheduler.firingDecision(
            in: schedules, state: controller.status(),
            firedWindowStart: firedWindowStart, at: now, calendar: .current
        ) {
        case .none:
            break
        case .skip(let windowStart):
            firedWindowStart = windowStart
        case .fire(let windowStart, let duration):
            firedWindowStart = windowStart
            do {
                try controller.start(duration: duration)
                onChange()
            } catch {
                logTampError("schedule start failed", error)
            }
        }
    }

    private func rearm(schedules: [Schedule], now: Date) {
        timer?.invalidate()
        timer = nil
        guard let next = Scheduler.nextTransition(in: schedules, after: now, calendar: .current) else {
            return
        }
        // Fire just past the transition so activeWindow sees the new window.
        let timer = Timer(
            fireAt: next.addingTimeInterval(1), interval: 0,
            target: self, selector: #selector(timerFired),
            userInfo: nil, repeats: false
        )
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func timerFired() {
        evaluate()
    }

    @objc private func didWake() {
        // The armed fire date may have passed while asleep; catch up now.
        evaluate()
    }
}
