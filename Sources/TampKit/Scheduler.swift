import Foundation

/// Pure window math over `[Schedule]` — no timers, no state. The menu bar app
/// wires these into real timers (`ScheduleRunner`); keeping the calendar
/// injectable makes the logic testable with fixed dates and time zones.
///
/// Concrete dates are always built through the calendar (never by adding
/// 86400s), so DST transitions resolve to sane wall-clock times.
public enum Scheduler {
    /// The enabled window containing `now`, with its concrete start/end dates.
    /// Overlapping windows resolve to the one ending last.
    public static func activeWindow(
        in schedules: [Schedule],
        at now: Date,
        calendar: Calendar = .current
    ) -> (schedule: Schedule, start: Date, end: Date)? {
        let weekday = calendar.component(.weekday, from: now)
        var best: (schedule: Schedule, start: Date, end: Date)?
        for schedule in schedules where schedule.enabled && schedule.weekdays.contains(weekday) {
            guard let start = schedule.start.date(onDayOf: now, calendar: calendar),
                  let end = schedule.end.date(onDayOf: now, calendar: calendar),
                  start <= now, now < end
            else { continue }
            if best.map({ end > $0.end }) ?? true {
                best = (schedule, start, end)
            }
        }
        return best
    }

    /// The next moment any enabled window starts or ends after `now`, or nil
    /// when there are no enabled schedules. Windows sit within a single day,
    /// so scanning day-by-day (a full week + 1) is exhaustive.
    public static func nextTransition(
        in schedules: [Schedule],
        after now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            var best: Date?
            for schedule in schedules where schedule.enabled && schedule.weekdays.contains(weekday) {
                for time in [schedule.start, schedule.end] {
                    if let date = time.date(onDayOf: day, calendar: calendar), date > now {
                        best = best.map { min($0, date) } ?? date
                    }
                }
            }
            // Later days only hold later transitions, so the first hit wins.
            if let best { return best }
        }
        return nil
    }

    /// What a schedule runner should do at `now` — the pure firing policy,
    /// kept here (not in the menu bar app) so it is testable and any future
    /// second runner can't drift on the semantics.
    public enum FiringDecision: Equatable, Sendable {
        /// Nothing to do (no active window, or this window was already handled).
        case none
        /// Start a timed session of `duration` seconds ending at the window end.
        case fire(windowStart: Date, duration: Int)
        /// A window is active but the current session outranks it — record the
        /// window as handled without touching the session.
        case skip(windowStart: Date)
    }

    /// Decide against the window containing `now`. `firedWindowStart` is the
    /// runner's edge-trigger marker (the last window start it handled).
    /// A current session outranks the window — and is never weakened — when it
    /// is indefinite, a while-app session, or a timed session ending at or
    /// after the window end.
    public static func firingDecision(
        in schedules: [Schedule],
        state: TampState,
        firedWindowStart: Date?,
        at now: Date,
        calendar: Calendar = .current
    ) -> FiringDecision {
        guard let window = activeWindow(in: schedules, at: now, calendar: calendar),
              firedWindowStart != window.start
        else { return .none }
        if state.active {
            let outranksWindow = state.watchedPID != nil
                || state.endsAt == nil
                || state.endsAt.map({ $0 >= window.end }) == true
            if outranksWindow { return .skip(windowStart: window.start) }
        }
        let seconds = Int(window.end.timeIntervalSince(now).rounded())
        guard seconds > 0 else { return .none }
        return .fire(windowStart: window.start, duration: seconds)
    }
}
