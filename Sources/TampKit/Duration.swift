import Foundation

/// Parsing helpers for `for <duration>` and `until <time>` requests.
public enum DurationParser {

    public enum ParseError: Error, CustomStringConvertible {
        case empty
        case invalid(String)
        case tooLong(String)

        public var description: String {
            switch self {
            case .empty:
                return "No duration given. Examples: 30m, 1h, 1h30m, 90s."
            case .invalid(let s):
                return "Could not parse \"\(s)\". Examples: 30m, 1h, 1h30m, 90s."
            case .tooLong(let s):
                return "\"\(s)\" is too long. Sessions are capped at 7 days."
            }
        }
    }

    /// Upper bound for a single session (7 days). Checking values against it
    /// *before* multiplying is also what keeps absurd inputs from overflowing
    /// Int and crashing.
    public static let maxSeconds = 7 * 24 * 3600

    /// Parse a compact duration like "1h30m", "45m", "90s", "2h" into seconds.
    /// A single leading "+" is allowed ("+15m"), matching how extensions are
    /// naturally typed.
    public static func seconds(from text: String) throws -> Int {
        var trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasPrefix("+") {
            // Re-trim so "+ 15m" works like "+15m".
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard !trimmed.isEmpty else { throw ParseError.empty }

        // Bare number means minutes (e.g. "90" → 90 minutes).
        if let bare = Int(trimmed) {
            guard bare > 0 else { throw ParseError.invalid(text) }
            guard bare <= maxSeconds / 60 else { throw ParseError.tooLong(text) }
            return bare * 60
        }

        var total = 0
        var matched = false
        var number = ""
        for ch in trimmed {
            if ch.isNumber {
                number.append(ch)
            } else {
                guard let value = Int(number) else { throw ParseError.invalid(text) }
                let unit: Int
                switch ch {
                case "h": unit = 3600
                case "m": unit = 60
                case "s": unit = 1
                default: throw ParseError.invalid(text)
                }
                guard value <= maxSeconds / unit, total + value * unit <= maxSeconds else {
                    throw ParseError.tooLong(text)
                }
                total += value * unit
                number = ""
                matched = true
            }
        }
        // Trailing digits with no unit are not allowed in compound form.
        guard matched, number.isEmpty, total > 0 else { throw ParseError.invalid(text) }
        return total
    }

    /// Parse an "until" clock time ("HH:MM", 24h) into seconds from `now`.
    /// If the time has already passed today, it is treated as tomorrow.
    public static func secondsUntil(
        time text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute)
        else { throw ParseError.invalid(text) }

        guard var target = TimeOfDay(hour: hour, minute: minute)
            .date(onDayOf: now, calendar: calendar)
        else { throw ParseError.invalid(text) }
        if target <= now {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: target) else {
                throw ParseError.invalid(text)
            }
            target = tomorrow
        }
        return Int(target.timeIntervalSince(now).rounded())
    }

    /// Format a date's wall-clock time as "HH:MM" (24h) — the same shape the
    /// `until` command accepts, used for end-time display.
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    /// The timed-session summary both front-ends show — "1h 7m left
    /// (until 17:30)" — single-sourced so the CLI and the menu bar can't
    /// drift on the one fragment that must stay identical.
    public static func remainingSummary(
        remaining: TimeInterval,
        endsAt: Date?,
        calendar: Calendar = .current
    ) -> String {
        let until = endsAt.map { " (until \(clock($0, calendar: calendar)))" } ?? ""
        return "\(format(remaining: remaining)) left\(until)"
    }

    /// Format a remaining interval as a compact human string ("1h 7m", "45s").
    public static func format(remaining seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}
