import Foundation
import TampKit

// Minimal assertion harness (no XCTest/Swift Testing available without Xcode).
var failures = 0
@MainActor func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok: \(message)")
    } else {
        failures += 1
        print("  FAIL: \(message)")
    }
}
@MainActor func checkThrows(_ message: String, _ body: () throws -> Void) {
    do {
        try body()
        failures += 1
        print("  FAIL: \(message) (expected throw)")
    } catch {
        print("  ok: \(message)")
    }
}

print("DurationParser")
check((try? DurationParser.seconds(from: "30m")) == 1800, "30m → 1800")
check((try? DurationParser.seconds(from: "1h")) == 3600, "1h → 3600")
check((try? DurationParser.seconds(from: "1h30m")) == 5400, "1h30m → 5400")
check((try? DurationParser.seconds(from: "90s")) == 90, "90s → 90")
check((try? DurationParser.seconds(from: "2h15m30s")) == 8130, "2h15m30s → 8130")
check((try? DurationParser.seconds(from: "90")) == 5400, "bare 90 → 90 minutes")
check((try? DurationParser.seconds(from: "+15m")) == 900, "+15m → 900 (leading + allowed)")
check((try? DurationParser.seconds(from: "+ 15m")) == 900, "+ 15m → 900 (space after + allowed)")
check((try? DurationParser.seconds(from: "+90")) == 5400, "+90 → 90 minutes")
checkThrows("bare + throws") { _ = try DurationParser.seconds(from: "+") }
checkThrows("empty string throws") { _ = try DurationParser.seconds(from: "") }
checkThrows("abc throws") { _ = try DurationParser.seconds(from: "abc") }
checkThrows("1h30 (trailing digits) throws") { _ = try DurationParser.seconds(from: "1h30") }
checkThrows("0m throws") { _ = try DurationParser.seconds(from: "0m") }
check((try? DurationParser.seconds(from: "168h")) == DurationParser.maxSeconds, "168h → exactly the 7-day cap")
checkThrows("169h (over cap) throws") { _ = try DurationParser.seconds(from: "169h") }
checkThrows("10081 bare minutes (over cap) throws") { _ = try DurationParser.seconds(from: "10081") }
checkThrows("167h100m (components under cap, total over) throws") { _ = try DurationParser.seconds(from: "167h100m") }
checkThrows("Int.max hours throws instead of crashing") {
    _ = try DurationParser.seconds(from: "9223372036854775807h")
}
checkThrows("Int.max bare minutes throws instead of crashing") {
    _ = try DurationParser.seconds(from: "9223372036854775807")
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 10, minute: 0))!
check((try? DurationParser.secondsUntil(time: "12:30", now: now, calendar: cal)) == 2 * 3600 + 30 * 60,
      "until 12:30 from 10:00 → 2h30m")
check((try? DurationParser.secondsUntil(time: "09:00", now: now, calendar: cal)) == 23 * 3600,
      "until 09:00 (past) rolls to tomorrow → 23h")

let evening = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 17, minute: 30))!
check(DurationParser.clock(evening, calendar: cal) == "17:30", "clock → 17:30")
let morning = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9, minute: 5))!
check(DurationParser.clock(morning, calendar: cal) == "09:05", "clock zero-pads → 09:05")

check(DurationParser.remainingSummary(remaining: 4020, endsAt: evening, calendar: cal)
        == "1h 7m left (until 17:30)",
      "remainingSummary composes remaining + end time")
check(DurationParser.remainingSummary(remaining: 4020, endsAt: nil) == "1h 7m left",
      "remainingSummary without endsAt omits the suffix")

check(DurationParser.format(remaining: 4020) == "1h 7m", "format 4020 → 1h 7m")
check(DurationParser.format(remaining: 2700) == "45m", "format 2700 → 45m")
check(DurationParser.format(remaining: 30) == "30s", "format 30 → 30s")
check(DurationParser.format(remaining: 3600) == "1h", "format 3600 → 1h")

print("SleepFlags")
check(SleepFlags(display: true, system: true, disk: false).caffeinateArguments == ["-d", "-i"],
      "display+system → -d -i")
check(SleepFlags(display: false, system: true, disk: true).caffeinateArguments == ["-i", "-m"],
      "system+disk → -i -m")
check(SleepFlags(display: false, system: false, disk: false).caffeinateArguments == [],
      "none → []")
check(SleepFlags(display: false, system: false, disk: false, acPower: true, wake: true)
        .caffeinateArguments == ["-s", "-u"],
      "acPower+wake → -s -u")
check(SleepFlags(display: true, system: true, disk: true, acPower: true, wake: true)
        .caffeinateArguments == ["-d", "-i", "-m", "-s", "-u"],
      "all five → -d -i -m -s -u (stable order)")
let wakeOnly = SleepFlags(display: false, system: false, disk: false, wake: true)
check(wakeOnly.sessionArguments(timed: false) == ["-u", "-i"],
      "untimed wake-only session gets the -i backstop")
check(wakeOnly.sessionArguments(timed: true) == ["-u"],
      "timed wake-only session keeps bare -u (-t sustains it)")
check(SleepFlags(display: false, system: false, disk: false).sessionArguments(timed: false) == ["-i"],
      "all-off session falls back to -i")

// A pre-1.1.0 state file (no acPower/wake keys) must keep decoding, with the
// newer flags defaulting to off and the stored values preserved.
print("Legacy state decode")
let legacyTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-legacy-\(UUID().uuidString).json")
let legacyJSON = """
{
  "active" : true,
  "endsAt" : "2027-01-15T12:00:00Z",
  "flags" : {
    "disk" : true,
    "display" : true,
    "system" : false
  },
  "pid" : 555
}
"""
try? legacyJSON.data(using: .utf8)?.write(to: legacyTmp)
let legacy = StateStore(url: legacyTmp).loadRaw()
check(legacy.active == true, "legacy file decodes (active preserved)")
check(legacy.pid == 555, "legacy pid preserved")
check(legacy.flags.system == false && legacy.flags.disk == true, "legacy flag values preserved")
check(legacy.flags.acPower == false && legacy.flags.wake == false, "missing new flags default to off")
check(legacy.watchedPID == nil && legacy.watchedName == nil, "missing watched fields default to nil")
try? FileManager.default.removeItem(at: legacyTmp)

print("StateStore")
let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-test-\(UUID().uuidString).json")
let store = StateStore(url: tmp)
let endsAt = Date(timeIntervalSince1970: 1_800_000_000)
store.save(TampState(
    active: true, pid: 4242,
    endsAt: endsAt,
    flags: SleepFlags(display: true, system: false, disk: true, acPower: true, wake: true)
))
let loaded = store.loadRaw()
check(loaded.active == true, "round-trip active")
check(loaded.pid == 4242, "round-trip pid")
check(loaded.endsAt == endsAt, "round-trip endsAt")
check(loaded.flags == SleepFlags(display: true, system: false, disk: true, acPower: true, wake: true),
      "round-trip flags (incl. acPower/wake)")
try? FileManager.default.removeItem(at: tmp)

let missing = StateStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-missing-\(UUID().uuidString).json"))
check(missing.loadRaw().active == false, "missing file → inactive")

print("CaffeinateController — PID identity")
// A recorded PID pointing at a live NON-caffeinate process (this test runner
// itself — simulating PID reuse after reboot/expiry) must reconcile to
// inactive, and stop() must not signal it.
let pidTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-pid-\(UUID().uuidString).json")
let pidStore = StateStore(url: pidTmp)
pidStore.save(TampState(active: true, pid: getpid()))
let pidController = CaffeinateController(store: pidStore)
check(pidController.status().active == false, "reused PID (live non-caffeinate) reconciles to inactive")
pidStore.save(TampState(active: true, pid: getpid()))
_ = pidController.stop() // surviving this call is the assertion
check(true, "stop() with reused PID did not kill this process")
try? FileManager.default.removeItem(at: pidTmp)

print("CaffeinateController — lifecycle")
let lifeTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-life-\(UUID().uuidString).json")
let lifeController = CaffeinateController(store: StateStore(url: lifeTmp))
do {
    let started = try lifeController.start(duration: 60)
    check(started.active && started.pid != nil, "start() records an active pid")
    check(lifeController.status().active, "status() keeps a live session active")
    let stopped = lifeController.stop()
    check(stopped.active == false, "stop() deactivates")
    if let pid = started.pid {
        var gone = false
        for _ in 0..<50 { // up to ~1s for SIGTERM to land
            if kill(pid, 0) != 0 { gone = true; break }
            usleep(20_000)
        }
        check(gone, "tracked caffeinate is gone after stop()")
    }
} catch {
    check(false, "lifecycle start() threw: \(error)")
}
try? FileManager.default.removeItem(at: lifeTmp)

print("CaffeinateController — extend")
let extTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-extend-\(UUID().uuidString).json")
let extController = CaffeinateController(store: StateStore(url: extTmp))
checkThrows("extend with no session throws") { try extController.extend(by: 60) }
do {
    let started = try extController.start(duration: 60)
    let extended = try extController.extend(by: 60)
    check(extended.active, "extend keeps the session active")
    check(extended.remaining().map { $0 > 100 && $0 <= 121 } == true, "extend 60s+60s → ≈120s remaining")
    check(extended.pid != nil && extended.pid != started.pid, "extend restarts with a fresh caffeinate")
    checkThrows("extend past the 7-day cap throws") { try extController.extend(by: DurationParser.maxSeconds) }
    check(extController.status().active, "over-cap extend leaves the session running")
    _ = extController.stop()
    _ = try extController.start() // indefinite
    checkThrows("extend on an indefinite session throws") { try extController.extend(by: 60) }
    _ = extController.stop()
} catch {
    check(false, "extend lifecycle threw: \(error)")
    _ = extController.stop()
}
try? FileManager.default.removeItem(at: extTmp)

print("ProcessResolver")
let selfPID = getpid()
check((try? ProcessResolver.resolve("\(selfPID)"))?.pid == selfPID, "resolve by PID finds this process")
if let selfName = (try? ProcessResolver.resolve("\(selfPID)"))?.name {
    do {
        _ = try ProcessResolver.resolve(selfName.uppercased())
        check(true, "resolve by name is case-insensitive")
    } catch ProcessResolver.ResolveError.ambiguous {
        // Another live process shares this name — still a correct, non-silent answer.
        check(true, "resolve by name is case-insensitive (ambiguous match reported)")
    } catch {
        check(false, "resolve by own name threw: \(error)")
    }
}
checkThrows("unknown name throws") {
    _ = try ProcessResolver.resolve("no-such-process-\(UUID().uuidString.prefix(8))")
}
checkThrows("dead PID throws") { _ = try ProcessResolver.resolve("999999") }

print("CaffeinateController — while-app lifecycle")
let whileTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-while-\(UUID().uuidString).json")
// Scratch prefs suite: the applyFlags check below persists flags, and the
// real shared suite must not be touched by the harness.
let whileSuite = "cz.kybernaut.tamp.checks.\(UUID().uuidString)"
let whileController = CaffeinateController(
    store: StateStore(url: whileTmp),
    preferences: Preferences(defaults: UserDefaults(suiteName: whileSuite))
)
checkThrows("startWhile on a dead pid throws") {
    _ = try whileController.startWhile(pid: 999_999, name: nil)
}
do {
    let sleeper = Process()
    sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
    sleeper.arguments = ["30"]
    try sleeper.run()
    let started = try whileController.startWhile(pid: sleeper.processIdentifier, name: "sleep")
    check(started.active && started.watchedPID == sleeper.processIdentifier,
          "startWhile records the watched pid")
    check(started.endsAt == nil, "while-app sessions are untimed")
    if case .onWhileApp(let name) = whileController.status().phase() {
        check(name == "sleep", "status phase is onWhileApp(sleep)")
    } else {
        check(false, "phase should be onWhileApp")
    }
    checkThrows("extend on a while-app session throws") { try whileController.extend(by: 60) }
    // Changing sleep prefs mid-session must keep watching (not drop -w).
    let reflagged = try whileController.applyFlags(SleepFlags(display: false, system: true, disk: false))
    check(reflagged.watchedPID == sleeper.processIdentifier && reflagged.endsAt == nil,
          "applyFlags keeps a while-app session watching")
    sleeper.terminate()
    sleeper.waitUntilExit()
    var ended = false
    for _ in 0..<150 { // caffeinate notices the watched process died (≤3s)
        if whileController.status().active == false { ended = true; break }
        usleep(20_000)
    }
    check(ended, "session reconciles to inactive after the watched process exits")
} catch {
    check(false, "while-app lifecycle threw: \(error)")
}
_ = whileController.stop()
try? FileManager.default.removeItem(at: whileTmp)
UserDefaults.standard.removePersistentDomain(forName: whileSuite)

print("TampState — while-app")
let watchedState = TampState(active: true, pid: 999, watchedPID: 4321, watchedName: "Xcode")
if case .onWhileApp(let name) = watchedState.phase() {
    check(name == "Xcode", "phase onWhileApp carries the app name")
} else {
    check(false, "watchedPID → phase onWhileApp")
}
let watchedReport = StatusReport(state: watchedState, systemActive: false)
check(watchedReport.phase == "onWhileApp", "report phase → onWhileApp")
check(watchedReport.remainingSeconds == nil, "onWhileApp → nil remaining")
let watchTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-watch-\(UUID().uuidString).json")
let watchStore = StateStore(url: watchTmp)
watchStore.save(watchedState)
let watchLoaded = watchStore.loadRaw()
check(watchLoaded.watchedPID == 4321 && watchLoaded.watchedName == "Xcode",
      "watched fields round-trip")
try? FileManager.default.removeItem(at: watchTmp)

print("TampState")
let nowState = Date()
let timed = TampState(active: true, endsAt: nowState.addingTimeInterval(600))
check(timed.remaining(now: nowState).map { abs($0 - 600) < 1 } == true, "remaining ≈ 600")
check(TampState.inactive().remaining() == nil, "inactive → nil remaining")

if case .onTimed(let r) = timed.phase(now: nowState) {
    check(abs(r - 600) < 1, "phase onTimed ≈ 600")
} else {
    check(false, "phase should be onTimed")
}
check(TampState.inactive().phase() == .off, "inactive → phase off")
check(TampState(active: true).phase() == .onIndefinite, "active, no endsAt → phase onIndefinite")

print("StatusReport")
let extReport = StatusReport(state: .inactive(), systemActive: true)
check(extReport.phase == "externallyActive", "inactive + systemActive → externallyActive")
check(extReport.remainingSeconds == nil, "externallyActive → nil remaining")
let timedReport = StatusReport(state: timed, systemActive: false, now: nowState)
check(timedReport.phase == "onTimed", "timed → onTimed")
check(timedReport.remainingSeconds.map { abs($0 - 600) <= 1 } == true, "timed → ≈600s remaining")
check(StatusReport(state: .inactive(), systemActive: false).phase == "off", "inactive → off")

print("ScheduleParser")
let weekdays = try? ScheduleParser.parse("weekdays 9-17")
check(weekdays?.weekdays == Set(2...6), "weekdays → Mon–Fri")
check(weekdays?.start == TimeOfDay(hour: 9, minute: 0)
        && weekdays?.end == TimeOfDay(hour: 17, minute: 0), "9-17 → 09:00–17:00")
check(weekdays?.displayText == "Weekdays 09:00–17:00", "normalized display text")
check(weekdays?.enabled == true, "new schedules start enabled")
check((try? ScheduleParser.parse("daily 8:30-18:15"))?.start == TimeOfDay(hour: 8, minute: 30),
      "8:30 parses minutes")
check((try? ScheduleParser.parse("every day 9-10"))?.weekdays == Set(1...7), "every day → all 7")
check((try? ScheduleParser.parse("weekends 10-14"))?.weekdays == Set([1, 7]), "weekends → Sat+Sun")
check((try? ScheduleParser.parse("mon,wed,fri 9am-5pm"))?.weekdays == Set([2, 4, 6]),
      "comma day list parses")
check((try? ScheduleParser.parse("mon,wed,fri 9am-5pm"))?.end == TimeOfDay(hour: 17, minute: 0),
      "5pm → 17:00")
check((try? ScheduleParser.parse("MON-FRI 7-9"))?.weekdays == Set(2...6),
      "day range, case-insensitive")
check((try? ScheduleParser.parse("fri-mon 7-9"))?.weekdays == Set([6, 7, 1, 2]),
      "wrapping day range fri-mon")
check((try? ScheduleParser.parse("daily 12am-12pm"))?.start == TimeOfDay(hour: 0, minute: 0),
      "12am → 00:00")
check((try? ScheduleParser.parse("daily 12am-12pm"))?.end == TimeOfDay(hour: 12, minute: 0),
      "12pm → 12:00")
checkThrows("empty schedule throws") { _ = try ScheduleParser.parse("") }
checkThrows("time range without days throws") { _ = try ScheduleParser.parse("9-17") }
checkThrows("unknown day throws") { _ = try ScheduleParser.parse("funday 9-17") }
checkThrows("overnight window throws") { _ = try ScheduleParser.parse("weekdays 17-9") }
checkThrows("zero-length window throws") { _ = try ScheduleParser.parse("daily 9-9") }
checkThrows("hour 25 throws") { _ = try ScheduleParser.parse("daily 9-25") }
checkThrows("13pm throws") { _ = try ScheduleParser.parse("daily 9am-13pm") }
checkThrows("leading dash throws") { _ = try ScheduleParser.parse("daily -9-17") }
checkThrows("double dash throws") { _ = try ScheduleParser.parse("daily 9--17") }
checkThrows("double dash in day range throws") { _ = try ScheduleParser.parse("mon--fri 9-17") }
checkThrows("one-digit minutes throw (9:5 is ambiguous)") { _ = try ScheduleParser.parse("daily 9:5-10") }

print("Scheduler")
// Fixed UTC calendar (`cal` above); 2026-06-15 is a Monday.
let workweek = Schedule(
    weekdays: Set(2...6),
    start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 17, minute: 0),
    displayText: "Weekdays 09:00–17:00"
)
let monday10 = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 10))!
let monday17 = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 17))!
let monday18 = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 18))!
let window = Scheduler.activeWindow(in: [workweek], at: monday10, calendar: cal)
check(window != nil, "inside a window → active")
check(window?.end == monday17, "window end is today 17:00")
check(window?.start == cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9)),
      "window start is today 09:00")
check(Scheduler.activeWindow(in: [workweek], at: monday18, calendar: cal) == nil,
      "after hours → no window")
let saturday10 = cal.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10))!
check(Scheduler.activeWindow(in: [workweek], at: saturday10, calendar: cal) == nil,
      "weekend → no window")
var disabledWeek = workweek
disabledWeek.enabled = false
check(Scheduler.activeWindow(in: [disabledWeek], at: monday10, calendar: cal) == nil,
      "disabled schedule is ignored")
let lateShift = Schedule(
    weekdays: Set(2...6),
    start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 19, minute: 0),
    displayText: "Weekdays 10:00–19:00"
)
let monday11 = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 11))!
let overlapping = Scheduler.activeWindow(in: [workweek, lateShift], at: monday11, calendar: cal)
check(overlapping?.end == cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 19)),
      "overlapping windows → latest end wins")
check(Scheduler.nextTransition(in: [workweek], after: monday10, calendar: cal) == monday17,
      "inside a window → next transition is its end")
let tuesday9 = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 9))!
check(Scheduler.nextTransition(in: [workweek], after: monday18, calendar: cal) == tuesday9,
      "after hours → next transition is tomorrow 09:00")
let friday18 = cal.date(from: DateComponents(year: 2026, month: 6, day: 19, hour: 18))!
let nextMonday9 = cal.date(from: DateComponents(year: 2026, month: 6, day: 22, hour: 9))!
check(Scheduler.nextTransition(in: [workweek], after: friday18, calendar: cal) == nextMonday9,
      "next transition skips the weekend")
check(Scheduler.nextTransition(in: [disabledWeek], after: monday10, calendar: cal) == nil,
      "no enabled schedules → no transition")

// Firing policy — pure and runner-independent, so a second runner (launchd)
// could never drift on the semantics.
let monday9 = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9))!
if case .fire(let start, let duration) = Scheduler.firingDecision(
    in: [workweek], state: .inactive(), firedWindowStart: nil, at: monday10, calendar: cal
) {
    check(start == monday9, "fire carries the window start")
    check(abs(duration - 7 * 3600) <= 1, "no session mid-window → fire until the window end")
} else {
    check(false, "no session mid-window should fire")
}
check(Scheduler.firingDecision(
        in: [workweek], state: TampState(active: true, pid: 1),
        firedWindowStart: nil, at: monday10, calendar: cal
      ) == .skip(windowStart: monday9),
      "indefinite session outranks the window → skip")
check(Scheduler.firingDecision(
        in: [workweek], state: TampState(active: true, pid: 1, watchedPID: 42, watchedName: "X"),
        firedWindowStart: nil, at: monday10, calendar: cal
      ) == .skip(windowStart: monday9),
      "while-app session outranks the window → skip")
if case .fire = Scheduler.firingDecision(
    in: [workweek], state: TampState(active: true, pid: 1, endsAt: monday10.addingTimeInterval(600)),
    firedWindowStart: nil, at: monday10, calendar: cal
) {
    check(true, "shorter timed session is replaced → fire")
} else {
    check(false, "shorter timed session is replaced → fire")
}
check(Scheduler.firingDecision(
        in: [workweek], state: .inactive(), firedWindowStart: monday9, at: monday10, calendar: cal
      ) == .none,
      "already-handled window → none (manual off stays off)")

// DST: Europe/Prague springs forward 2026-03-29 (02:00 → 03:00). A window
// whose start falls into the gap must still resolve without crashing.
var prague = Calendar(identifier: .gregorian)
prague.timeZone = TimeZone(identifier: "Europe/Prague")!
let gapSchedule = Schedule(
    weekdays: Set(1...7),
    start: TimeOfDay(hour: 2, minute: 30), end: TimeOfDay(hour: 4, minute: 0),
    displayText: "Daily 02:30–04:00"
)
let beforeGap = prague.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 1))!
check(Scheduler.nextTransition(in: [gapSchedule], after: beforeGap, calendar: prague) != nil,
      "spring-forward gap still yields a transition (no crash)")

print("ScheduleStore")
let schedTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-sched-\(UUID().uuidString).json")
let schedStore = ScheduleStore(url: schedTmp)
schedStore.save([workweek, disabledWeek])
check(schedStore.load() == [workweek, disabledWeek], "schedules round-trip (incl. enabled flag)")
try? FileManager.default.removeItem(at: schedTmp)
let schedMissing = ScheduleStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-sched-missing-\(UUID().uuidString).json"))
check(schedMissing.load().isEmpty, "missing schedules file → []")

print("")
if failures == 0 {
    print("All checks passed.")
} else {
    print("\(failures) check(s) FAILED.")
    exit(1)
}
