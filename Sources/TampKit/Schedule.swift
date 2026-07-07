import Foundation

/// A wall-clock time of day (24h).
public struct TimeOfDay: Codable, Equatable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    /// Zero-padded "09:05".
    public var display: String { String(format: "%02d:%02d", hour, minute) }
}

/// A recurring keep-awake window: a set of weekdays and a start–end time
/// within a single day (windows never cross midnight — see `ScheduleParser`).
public struct Schedule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// `Calendar` weekday numbers (1 = Sunday … 7 = Saturday).
    public var weekdays: Set<Int>
    public var start: TimeOfDay
    public var end: TimeOfDay
    public var enabled: Bool
    /// The normalized human form ("Weekdays 09:00–17:00") shown in menus/CLI.
    public var displayText: String

    public init(
        id: UUID = UUID(),
        weekdays: Set<Int>,
        start: TimeOfDay,
        end: TimeOfDay,
        enabled: Bool = true,
        displayText: String
    ) {
        self.id = id
        self.weekdays = weekdays
        self.start = start
        self.end = end
        self.enabled = enabled
        self.displayText = displayText
    }
}

/// Deterministic parser for natural-language schedules like "weekdays 9-17",
/// "daily 8:30-18:15", "mon,wed,fri 9am-5pm", "mon-fri 7-9". The last
/// whitespace-separated token is the time range; everything before it is the
/// required day spec — a bare "9-17" is rejected rather than guessing days.
public enum ScheduleParser {
    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case empty
        case missingDays(String)
        case badDays(String)
        case badTime(String)
        case emptyWindow(String)
        case overnight(String)

        public var description: String {
            switch self {
            case .empty:
                return "No schedule given. Examples: \"weekdays 9-17\", \"mon,wed,fri 9am-5pm\"."
            case .missingDays(let s):
                return "\"\(s)\" needs days before the time range, e.g. \"daily 9-17\"."
            case .badDays(let s):
                return "Could not read the days in \"\(s)\". Use daily, weekdays, weekends, "
                    + "or day names like mon,wed,fri (ranges work too: mon-fri)."
            case .badTime(let s):
                return "Could not read the time range in \"\(s)\". "
                    + "Use 24h times like 9-17 or 8:30-18:15, or 9am-5pm."
            case .emptyWindow(let s):
                return "\"\(s)\" starts and ends at the same time."
            case .overnight(let s):
                return "\"\(s)\" crosses midnight — overnight windows aren't supported yet. "
                    + "Split it into an evening and a morning schedule."
            }
        }
    }

    private static let dayNames: [String: Int] = [
        "sun": 1, "sunday": 1,
        "mon": 2, "monday": 2,
        "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "wednesday": 4,
        "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6,
        "sat": 7, "saturday": 7,
    ]

    public static func parse(_ text: String) throws -> Schedule {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { throw ParseError.empty }
        var tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 2, let timeToken = tokens.popLast() else {
            throw ParseError.missingDays(text)
        }
        let weekdays = try weekdays(from: tokens.joined(separator: " "), original: text)
        let (start, end) = try timeRange(from: timeToken, original: text)
        guard start != end else { throw ParseError.emptyWindow(text) }
        guard start < end else { throw ParseError.overnight(text) }
        return Schedule(
            weekdays: weekdays, start: start, end: end,
            displayText: displayText(weekdays: weekdays, start: start, end: end)
        )
    }

    private static func weekdays(from spec: String, original: String) throws -> Set<Int> {
        switch spec {
        case "daily", "everyday", "every day": return Set(1...7)
        case "weekdays": return Set(2...6)
        case "weekends": return [1, 7]
        default: break
        }
        var days: Set<Int> = []
        for part in spec.replacingOccurrences(of: " ", with: "").split(separator: ",").map(String.init) {
            if part.contains("-") || part.contains("–") {
                // Keep empty subsequences so "mon--fri" or a stray leading
                // dash is rejected instead of silently collapsing.
                let bounds = part
                    .split(whereSeparator: { $0 == "-" || $0 == "–" }, omittingEmptySubsequences: false)
                    .map(String.init)
                guard bounds.count == 2,
                      let from = dayNames[bounds[0]], let to = dayNames[bounds[1]]
                else { throw ParseError.badDays(original) }
                var day = from
                while true {
                    days.insert(day)
                    if day == to { break }
                    day = day % 7 + 1 // wraps, so "fri-mon" works
                }
            } else if let day = dayNames[part] {
                days.insert(day)
            } else {
                throw ParseError.badDays(original)
            }
        }
        guard !days.isEmpty else { throw ParseError.badDays(original) }
        return days
    }

    private static func timeRange(from token: String, original: String) throws -> (TimeOfDay, TimeOfDay) {
        // Keep empty subsequences so "-9-17" and "9--17" are rejected instead
        // of a stray dash silently vanishing.
        let bounds = token
            .split(whereSeparator: { $0 == "-" || $0 == "–" }, omittingEmptySubsequences: false)
            .map(String.init)
        guard bounds.count == 2 else { throw ParseError.badTime(original) }
        return (try timeOfDay(bounds[0], original: original),
                try timeOfDay(bounds[1], original: original))
    }

    private static func timeOfDay(_ raw: String, original: String) throws -> TimeOfDay {
        var text = raw
        var meridiem: String?
        if text.hasSuffix("am") || text.hasSuffix("pm") {
            meridiem = String(text.suffix(2))
            text = String(text.dropLast(2))
        }
        let parts = text.split(separator: ":").map(String.init)
        guard (1...2).contains(parts.count), let hourRaw = Int(parts[0]) else {
            throw ParseError.badTime(original)
        }
        // Minutes must be two digits ("9:5" is ambiguous — 9:05 or 9:50?).
        let minuteRaw = parts.count == 2 ? (parts[1].count == 2 ? Int(parts[1]) : nil) : 0
        guard let minute = minuteRaw, (0..<60).contains(minute) else {
            throw ParseError.badTime(original)
        }
        let hour: Int
        if let meridiem {
            guard (1...12).contains(hourRaw) else { throw ParseError.badTime(original) }
            hour = hourRaw % 12 + (meridiem == "pm" ? 12 : 0)
        } else {
            guard (0..<24).contains(hourRaw) else { throw ParseError.badTime(original) }
            hour = hourRaw
        }
        return TimeOfDay(hour: hour, minute: minute)
    }

    private static func displayText(weekdays: Set<Int>, start: TimeOfDay, end: TimeOfDay) -> String {
        let days: String
        if weekdays == Set(1...7) {
            days = "Daily"
        } else if weekdays == Set(2...6) {
            days = "Weekdays"
        } else if weekdays == [1, 7] {
            days = "Weekends"
        } else {
            let labels = [2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat", 1: "Sun"]
            days = [2, 3, 4, 5, 6, 7, 1] // week shown starting Monday
                .filter(weekdays.contains)
                .compactMap { labels[$0] }
                .joined(separator: ", ")
        }
        return "\(days) \(start.display)–\(end.display)"
    }
}
