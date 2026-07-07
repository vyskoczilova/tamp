import ArgumentParser
import TampKit
import Foundation

@main
struct Tamp: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tamp",
        abstract: """
        Keep your Mac awake. Karolína Vyskočilová's wrapper around the native \
        macOS caffeinate command — tracks its own sessions and shows when other \
        apps keep the Mac awake. Inspired by the Raycast Coffee extension.
        """,
        version: appVersion,
        subcommands: [
            On.self, Off.self, Toggle.self, For.self, Until.self, While.self,
            Add.self, ScheduleCommand.self, Status.self, Icon.self,
        ],
        defaultSubcommand: Status.self
    )
}

/// Flags shared by commands that start a session, letting a single run override
/// the saved sleep preferences.
struct SleepOverrides: ParsableArguments {
    @Flag(name: .long, inversion: .prefixedNo, help: "Prevent the display from sleeping.")
    var display: Bool?

    @Flag(name: .long, inversion: .prefixedNo, help: "Prevent the system from idle sleeping.")
    var system: Bool?

    @Flag(name: .long, inversion: .prefixedNo, help: "Prevent the disk from idle sleeping.")
    var disk: Bool?

    @Flag(
        name: .customLong("ac"), inversion: .prefixedNo,
        help: "Prevent system sleep only while on AC power (no effect on battery)."
    )
    var acPower: Bool?

    @Flag(
        name: .customLong("wake"), inversion: .prefixedNo,
        help: "Wake the display when the session starts (held for timed sessions only)."
    )
    var wake: Bool?

    /// Returns flags only if the user overrode at least one; otherwise nil so
    /// the engine falls back to saved preferences.
    func resolved() -> SleepFlags? {
        guard display != nil || system != nil || disk != nil
                || acPower != nil || wake != nil
        else { return nil }
        let base = Preferences().sleepFlags
        return SleepFlags(
            display: display ?? base.display,
            system: system ?? base.system,
            disk: disk ?? base.disk,
            acPower: acPower ?? base.acPower,
            wake: wake ?? base.wake
        )
    }
}

struct On: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Keep awake indefinitely.")
    @OptionGroup var overrides: SleepOverrides

    func run() throws {
        let state = try CaffeinateController().start(flags: overrides.resolved())
        print(describe(state))
    }
}

struct Off: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Allow sleep again.")
    func run() throws {
        let state = CaffeinateController().stop()
        print(describe(state, systemActive: SystemAssertions.isCaffeinated()))
    }
}

struct Toggle: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Toggle keep-awake on/off.")
    func run() throws {
        let state = try CaffeinateController().toggle()
        print(describe(state, systemActive: SystemAssertions.isCaffeinated()))
    }
}

struct For: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "for",
        abstract: "Keep awake for a duration, e.g. 'tamp for 2h' or '1h30m'."
    )
    @Argument(help: "Duration: 30m, 1h, 1h30m, 90s (bare number = minutes).")
    var duration: String
    @OptionGroup var overrides: SleepOverrides

    func run() throws {
        let seconds = try DurationParser.seconds(from: duration)
        let state = try CaffeinateController().start(duration: seconds, flags: overrides.resolved())
        print(describe(state))
    }
}

struct Until: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Keep awake until a clock time, e.g. 'tamp until 17:30'."
    )
    @Argument(help: "Time in 24h HH:MM. Past times roll to tomorrow.")
    var time: String
    @OptionGroup var overrides: SleepOverrides

    func run() throws {
        let seconds = try DurationParser.secondsUntil(time: time)
        let state = try CaffeinateController().start(duration: seconds, flags: overrides.resolved())
        print(describe(state))
    }
}

struct While: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "while",
        abstract: "Keep awake while another app or process runs, e.g. 'tamp while Xcode'.",
        discussion: """
        The target is an exact process name (case-insensitive) or a PID. The \
        session follows that specific process and ends when it exits — \
        relaunching the app does not re-arm it. If several processes share the \
        name, their PIDs are listed so you can pick one. (Process names longer \
        than 32 characters are truncated by the system; use a PID for those.)
        """
    )
    @Argument(help: "Process name (exact, case-insensitive) or PID.")
    var target: [String]
    @OptionGroup var overrides: SleepOverrides

    func run() throws {
        let joined = target.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !joined.isEmpty else { throw ValidationError("Give an app name or PID.") }
        let resolved = try ProcessResolver.resolve(joined)
        let state = try CaffeinateController().startWhile(
            pid: resolved.pid, name: resolved.name, flags: overrides.resolved()
        )
        print(describe(state))
    }
}

struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Extend the current timed session, e.g. 'tamp add 15m'."
    )
    @Argument(help: "Extra time: 15m, 1h, +30m (bare number = minutes).")
    var duration: String

    func run() throws {
        let seconds = try DurationParser.seconds(from: duration)
        let state = try CaffeinateController().extend(by: seconds)
        print(describe(state))
    }
}

struct ScheduleCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schedule",
        abstract: "Manage recurring keep-awake schedules.",
        discussion: scheduleRuntimeNote,
        subcommands: [
            ScheduleAdd.self, ScheduleList.self, ScheduleRemove.self,
            ScheduleEnable.self, ScheduleDisable.self,
        ],
        defaultSubcommand: ScheduleList.self
    )
}

let scheduleRuntimeNote = "Schedules run while the Tamp menu bar app is running."

/// Look up a 1-based schedule number from `tamp schedule list`.
func scheduleIndex(_ number: Int, in schedules: [Schedule]) throws -> Int {
    guard number >= 1, number <= schedules.count else {
        throw ValidationError("No schedule #\(number). Run 'tamp schedule list'.")
    }
    return number - 1
}

struct ScheduleAdd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a schedule, e.g. 'tamp schedule add weekdays 9-17'."
    )
    @Argument(help: "Days + time range: weekdays 9-17, daily 8:30-18, mon,wed,fri 9am-5pm.")
    var schedule: [String]

    func run() throws {
        let parsed = try ScheduleParser.parse(schedule.joined(separator: " "))
        let store = ScheduleStore()
        var schedules = store.load()
        schedules.append(parsed)
        store.save(schedules) // a running menu bar app watches this file
        print("Added: \(parsed.displayText)")
        print(scheduleRuntimeNote)
    }
}

struct ScheduleList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List schedules ( * marks enabled )."
    )

    func run() throws {
        let schedules = ScheduleStore().load()
        guard !schedules.isEmpty else {
            print("No schedules. Add one with 'tamp schedule add weekdays 9-17'.")
            return
        }
        for (index, schedule) in schedules.enumerated() {
            let marker = schedule.enabled ? "*" : " "
            print("\(marker) \(index + 1). \(schedule.displayText)")
        }
        print(scheduleRuntimeNote)
    }
}

struct ScheduleRemove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a schedule by its list number."
    )
    @Argument(help: "Schedule number from 'tamp schedule list'.")
    var number: Int

    func run() throws {
        let store = ScheduleStore()
        var schedules = store.load()
        let removed = schedules.remove(at: try scheduleIndex(number, in: schedules))
        store.save(schedules)
        print("Removed: \(removed.displayText)")
    }
}

/// Shared body of `schedule enable` / `schedule disable`.
func setScheduleEnabled(_ number: Int, to enabled: Bool) throws {
    let store = ScheduleStore()
    var schedules = store.load()
    let index = try scheduleIndex(number, in: schedules)
    schedules[index].enabled = enabled
    store.save(schedules)
    print("\(enabled ? "Enabled" : "Disabled"): \(schedules[index].displayText)")
}

struct ScheduleEnable: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable",
        abstract: "Enable a schedule by its list number."
    )
    @Argument(help: "Schedule number from 'tamp schedule list'.")
    var number: Int

    func run() throws {
        try setScheduleEnabled(number, to: true)
    }
}

struct ScheduleDisable: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable",
        abstract: "Disable a schedule by its list number (keeps it in the list)."
    )
    @Argument(help: "Schedule number from 'tamp schedule list'.")
    var number: Int

    func run() throws {
        try setScheduleEnabled(number, to: false)
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show current state.")
    @Flag(name: .long, help: "Output machine-readable JSON.")
    var json = false

    func run() throws {
        let state = CaffeinateController().status()
        if json {
            let report = StatusReport(state: state, systemActive: SystemAssertions.isCaffeinated())
            let data = try JSONEncoder.tamp.encode(report)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(describe(state, systemActive: SystemAssertions.isCaffeinated()))
        }
    }
}

struct Icon: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Get or set the menu bar icon style."
    )
    @Argument(help: "Style to set. Omit to list available styles and the current one.")
    var style: String?

    func run() throws {
        let prefs = Preferences()
        guard let style else {
            for s in IconStyle.allCases {
                let marker = s == prefs.iconStyle ? "*" : " "
                print("\(marker) \(s.rawValue) — \(s.label)")
            }
            return
        }
        guard let chosen = IconStyle(rawValue: style) else {
            let names = IconStyle.allCases.map(\.rawValue).joined(separator: ", ")
            throw ValidationError("Unknown style \"\(style)\". Choose one of: \(names).")
        }
        prefs.iconStyle = chosen
        // Poke the shared state file so a running menu bar app notices the new
        // style immediately — it watches the file, not UserDefaults, and an
        // indefinite session has no poll timer to pick the change up otherwise.
        StateStore().save(CaffeinateController().status())
        print("Icon style set to \(chosen.label).")
    }
}

/// Render a state as a one-line human summary.
func describe(_ state: TampState, systemActive: Bool = false) -> String {
    switch state.phase(systemActive: systemActive) {
    case .off:
        return "☕️ Off — your Mac can sleep normally."
    case .onTimed(let remaining):
        return "☕️ On — \(DurationParser.remainingSummary(remaining: remaining, endsAt: state.endsAt))."
    case .onIndefinite:
        return "☕️ On — staying awake until turned off."
    case .onWhileApp(let name):
        return "☕️ On — while \(name) runs."
    case .externallyActive:
        return "☕️ On — caffeinated by another app."
    }
}
