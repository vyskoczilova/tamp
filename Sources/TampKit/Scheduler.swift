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
            guard let start = date(of: schedule.start, onDayOf: now, calendar: calendar),
                  let end = date(of: schedule.end, onDayOf: now, calendar: calendar),
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
                    if let date = date(of: time, onDayOf: day, calendar: calendar), date > now {
                        best = best.map { min($0, date) } ?? date
                    }
                }
            }
            // Later days only hold later transitions, so the first hit wins.
            if let best { return best }
        }
        return nil
    }

    /// The wall-clock `time` on the same calendar day as `date` (mirrors
    /// `DurationParser.secondsUntil`'s construction).
    private static func date(of time: TimeOfDay, onDayOf date: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components)
    }
}
