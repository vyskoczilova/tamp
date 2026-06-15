import Foundation

/// Parsing helpers for `for <duration>` and `until <time>` requests.
public enum DurationParser {

    public enum ParseError: Error, CustomStringConvertible {
        case empty
        case invalid(String)
        case timeInPast(String)

        public var description: String {
            switch self {
            case .empty:
                return "No duration given. Examples: 30m, 1h, 1h30m, 90s."
            case .invalid(let s):
                return "Could not parse \"\(s)\". Examples: 30m, 1h, 1h30m, 90s."
            case .timeInPast(let s):
                return "\"\(s)\" is not in the future today. Use HH:MM (24h), e.g. 17:30."
            }
        }
    }

    /// Parse a compact duration like "1h30m", "45m", "90s", "2h" into seconds.
    public static func seconds(from text: String) throws -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { throw ParseError.empty }

        // Bare number means minutes (e.g. "90" → 90 minutes).
        if let bare = Int(trimmed) {
            guard bare > 0 else { throw ParseError.invalid(text) }
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
                switch ch {
                case "h": total += value * 3600
                case "m": total += value * 60
                case "s": total += value
                default: throw ParseError.invalid(text)
                }
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

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard var target = calendar.date(from: components) else {
            throw ParseError.invalid(text)
        }
        if target <= now {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: target) else {
                throw ParseError.invalid(text)
            }
            target = tomorrow
        }
        return Int(target.timeIntervalSince(now).rounded())
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
