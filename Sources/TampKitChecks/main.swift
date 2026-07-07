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
    .appendingPathComponent("tamp-test-\(UUID().uuidString).json")
let store = StateStore(url: tmp)
let endsAt = Date(timeIntervalSince1970: 1_800_000_000)
store.save(TampState(
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

print("ExternalCaffeination")
let bashSource = ExternalCaffeination(pid: 4321, parentPID: 1234, parentName: "bash")
check(bashSource.sourceDescription == "bash (pid 1234)", "named parent → 'bash (pid 1234)'")
let orphanSource = ExternalCaffeination(pid: 4321, parentPID: 1, parentName: "launchd")
check(orphanSource.sourceDescription == "an orphaned caffeinate (pid 4321 — parent exited)",
      "orphan wording names the caffeinate pid, not launchd")
check(ExternalCaffeination(pid: 4321, parentPID: nil, parentName: nil).sourceDescription
      == "an unidentified process (caffeinate pid 4321)", "unreadable parent → unidentified")
check(ExternalCaffeination(pid: 4321, parentPID: 1234, parentName: nil).sourceDescription
      == "pid 1234", "unnamed parent → bare pid")
check([ExternalCaffeination]().sourceSummary == "another app", "no sources → 'another app' fallback")
check([bashSource].sourceSummary == "bash (pid 1234)", "single source summary")
check([bashSource, orphanSource].sourceSummary == "bash (pid 1234) and 1 more",
      "multiple sources → 'and 1 more'")
check(TampState(active: true).externalSources().isEmpty,
      "externalSources() skips the scan while a session is active")

print("SystemAssertions — live parent resolution")
do {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
    child.arguments = ["-i", "-t", "30"]
    try child.run()
    let childPID = child.processIdentifier
    var found: ExternalCaffeination?
    for _ in 0..<50 { // up to ~1s for the child to appear in the scan
        if let hit = SystemAssertions.externalCaffeinations().first(where: { $0.pid == childPID }) {
            found = hit
            break
        }
        usleep(20_000)
    }
    check(found != nil, "spawned caffeinate appears in externalCaffeinations()")
    check(found?.parentPID == getpid(), "its parent resolves to this test runner's pid")
    check(found?.parentName == "TampKitChecks", "its parent name resolves to the test runner")
    child.terminate()
    child.waitUntilExit()
} catch {
    check(false, "spawning caffeinate threw: \(error)")
}

print("StatusReport")
let extReport = StatusReport(state: .inactive(), externalSources: [bashSource])
check(extReport.phase == "externallyActive", "inactive + external source → externallyActive")
check(extReport.remainingSeconds == nil, "externallyActive → nil remaining")
check(extReport.externalSources == [bashSource], "externallyActive → sources in the report")
let timedReport = StatusReport(state: timed, now: nowState)
check(timedReport.phase == "onTimed", "timed → onTimed")
check(timedReport.remainingSeconds.map { abs($0 - 600) <= 1 } == true, "timed → ≈600s remaining")
check(timedReport.externalSources == nil, "onTimed → no external sources")
check(StatusReport(state: .inactive()).phase == "off", "inactive → off")
check(StatusReport(state: .inactive()).externalSources == nil, "off → no external sources")

print("")
if failures == 0 {
    print("All checks passed.")
} else {
    print("\(failures) check(s) FAILED.")
    exit(1)
}
