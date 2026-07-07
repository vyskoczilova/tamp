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

print("")
if failures == 0 {
    print("All checks passed.")
} else {
    print("\(failures) check(s) FAILED.")
    exit(1)
}
