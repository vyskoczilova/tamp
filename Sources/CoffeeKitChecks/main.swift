import Foundation
import CoffeeKit

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

print("StateStore")
let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("coffee-test-\(UUID().uuidString).json")
let store = StateStore(url: tmp)
let endsAt = Date(timeIntervalSince1970: 1_800_000_000)
store.save(CoffeeState(
    active: true, pid: 4242,
    endsAt: endsAt,
    flags: SleepFlags(display: true, system: false, disk: true)
))
let loaded = store.loadRaw()
check(loaded.active == true, "round-trip active")
check(loaded.pid == 4242, "round-trip pid")
check(loaded.endsAt == endsAt, "round-trip endsAt")
check(loaded.flags == SleepFlags(display: true, system: false, disk: true), "round-trip flags")
try? FileManager.default.removeItem(at: tmp)

let missing = StateStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("coffee-missing-\(UUID().uuidString).json"))
check(missing.loadRaw().active == false, "missing file → inactive")

print("CaffeinateController — PID identity")
// A recorded PID pointing at a live NON-caffeinate process (this test runner
// itself — simulating PID reuse after reboot/expiry) must reconcile to
// inactive, and stop() must not signal it.
let pidTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("coffee-pid-\(UUID().uuidString).json")
let pidStore = StateStore(url: pidTmp)
pidStore.save(CoffeeState(active: true, pid: getpid()))
let pidController = CaffeinateController(store: pidStore)
check(pidController.status().active == false, "reused PID (live non-caffeinate) reconciles to inactive")
pidStore.save(CoffeeState(active: true, pid: getpid()))
_ = pidController.stop() // surviving this call is the assertion
check(true, "stop() with reused PID did not kill this process")
try? FileManager.default.removeItem(at: pidTmp)

print("CaffeinateController — lifecycle")
let lifeTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("coffee-life-\(UUID().uuidString).json")
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

print("CoffeeState")
let nowState = Date()
let timed = CoffeeState(active: true, endsAt: nowState.addingTimeInterval(600))
check(timed.remaining(now: nowState).map { abs($0 - 600) < 1 } == true, "remaining ≈ 600")
check(CoffeeState.inactive().remaining() == nil, "inactive → nil remaining")

if case .onTimed(let r) = timed.phase(now: nowState) {
    check(abs(r - 600) < 1, "phase onTimed ≈ 600")
} else {
    check(false, "phase should be onTimed")
}
check(CoffeeState.inactive().phase() == .off, "inactive → phase off")
check(CoffeeState(active: true).phase() == .onIndefinite, "active, no endsAt → phase onIndefinite")

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
