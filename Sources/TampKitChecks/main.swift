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

print("StatusReport")
let extReport = StatusReport(state: .inactive(), systemActive: true)
check(extReport.phase == "externallyActive", "inactive + systemActive → externallyActive")
check(extReport.remainingSeconds == nil, "externallyActive → nil remaining")
let timedReport = StatusReport(state: timed, systemActive: false, now: nowState)
check(timedReport.phase == "onTimed", "timed → onTimed")
check(timedReport.remainingSeconds.map { abs($0 - 600) <= 1 } == true, "timed → ≈600s remaining")
check(StatusReport(state: .inactive(), systemActive: false).phase == "off", "inactive → off")

print("TampState — holders")
// A state file written before the holders field existed must keep decoding.
let legacyJSON = #"{"active":false,"flags":{"display":true,"system":true,"disk":false}}"#
let legacy = try? JSONDecoder.tamp.decode(TampState.self, from: Data(legacyJSON.utf8))
check(legacy?.holders.isEmpty == true, "pre-holders state file decodes with empty holders")

let holdersTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-holders-\(UUID().uuidString).json")
let holdersStore = StateStore(url: holdersTmp)
holdersStore.save(TampState(holders: [
    TampState.Holder(id: "a"),
    TampState.Holder(id: "b", expiresAt: endsAt),
]))
let loadedHolders = holdersStore.loadRaw()
check(loadedHolders.holders.map(\.id) == ["a", "b"], "holders round-trip ids")
check(loadedHolders.holders.last?.expiresAt == endsAt, "holder expiresAt round-trips")
try? FileManager.default.removeItem(at: holdersTmp)

let mixed = TampState(holders: [
    TampState.Holder(id: "live"),
    TampState.Holder(id: "gone", expiresAt: Date(timeIntervalSinceNow: -10)),
])
check(mixed.liveHolders().map(\.id) == ["live"], "expired holders are filtered from liveHolders")
check(mixed.phase() == .heldBy(count: 1), "holders-only state → phase heldBy(1)")
check(mixed.phase(systemActive: true) == .heldBy(count: 1), "heldBy outranks externallyActive")
check(TampState(active: true, holders: [TampState.Holder(id: "x")]).phase() == .onIndefinite,
      "manual session outranks holds in phase")

print("StatusReport — holders")
let heldReport = StatusReport(state: TampState(holders: [TampState.Holder(id: "x")]), systemActive: false)
check(heldReport.phase == "heldBy", "holders-only → heldBy report phase")
check(heldReport.holders == ["x"], "report lists live holder ids")

print("StateStore — mutate")
let mutTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-mutate-\(UUID().uuidString).json")
let mutStore = StateStore(url: mutTmp)
mutStore.mutate { $0.holders.append(TampState.Holder(id: "one")) }
mutStore.mutate { $0.holders.append(TampState.Holder(id: "two")) }
check(mutStore.loadRaw().holders.map(\.id) == ["one", "two"], "mutate is read-modify-write, not overwrite")
try? FileManager.default.removeItem(at: mutTmp)

print("CaffeinateController — hold/release refcounting")
let refTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-ref-\(UUID().uuidString).json")
let refController = CaffeinateController(store: StateStore(url: refTmp))
do {
    let h1 = try refController.hold("checks-a")
    check(h1.active == false && h1.pid != nil, "first hold spawns caffeinate without a manual session")
    let firstPid = h1.pid
    let h2 = try refController.hold("checks-b")
    check(h2.pid == firstPid, "second hold reuses the same caffeinate")
    check(h2.liveHolders().count == 2, "two holds registered")
    let repeated = try refController.hold("checks-a")
    check(repeated.liveHolders().count == 2, "re-holding the same id is idempotent")
    let r1 = try refController.release("checks-a")
    check(r1.liveHolders().map(\.id) == ["checks-b"], "release removes exactly its own hold")
    check(firstPid.map { kill($0, 0) == 0 } == true, "caffeinate survives a partial release")
    let r2 = try refController.release("checks-b")
    check(r2.pid == nil && r2.holders.isEmpty, "last release clears the tracked pid")
    if let pid = firstPid {
        var gone = false
        for _ in 0..<50 {
            if kill(pid, 0) != 0 { gone = true; break }
            usleep(20_000)
        }
        check(gone, "caffeinate is gone after the last release")
    }
    let r3 = try refController.release("never-held")
    check(r3.active == false && r3.holders.isEmpty, "releasing an unknown id is a safe no-op")
} catch {
    check(false, "hold/release threw: \(error)")
}
try? FileManager.default.removeItem(at: refTmp)

print("CaffeinateController — holds vs manual session")
let mixTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-mix-\(UUID().uuidString).json")
let mixController = CaffeinateController(store: StateStore(url: mixTmp))
do {
    _ = try mixController.hold("bg")
    let manual = try mixController.start()
    check(manual.active && manual.liveHolders().map(\.id) == ["bg"], "manual start preserves holds")
    let released = try mixController.release("bg")
    check(released.active && released.pid != nil, "releasing under a manual session keeps it running")
    _ = try mixController.hold("bg2")
    let stopped = mixController.stop()
    check(stopped.active == false && stopped.holders.isEmpty && stopped.pid == nil,
          "manual off hard-stops holds too")
    _ = try mixController.hold("toggled")
    let afterToggle = try mixController.toggle()
    check(afterToggle.active == false && afterToggle.holders.isEmpty,
          "toggle treats holds as on and stops them")
} catch {
    check(false, "holds vs manual threw: \(error)")
}
try? FileManager.default.removeItem(at: mixTmp)

print("CaffeinateController — hold survives a dead session process")
let surviveTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-survive-\(UUID().uuidString).json")
let surviveController = CaffeinateController(store: StateStore(url: surviveTmp))
do {
    let started = try surviveController.start(duration: 60)
    _ = try surviveController.hold("survivor")
    if let pid = started.pid {
        kill(pid, SIGTERM)
        for _ in 0..<50 {
            if kill(pid, 0) != 0 { break }
            usleep(20_000)
        }
    }
    let settled = surviveController.status()
    check(settled.active == false, "dead manual session reconciles to inactive")
    check(settled.liveHolders().map(\.id) == ["survivor"], "hold survives the dead session")
    check(settled.pid.map { kill($0, 0) == 0 } == true, "a replacement caffeinate was spawned for the hold")
    let drained = surviveController.releaseAll()
    check(drained.holders.isEmpty && drained.pid == nil, "releaseAll drains holds and stops")
} catch {
    check(false, "hold-survives threw: \(error)")
}
try? FileManager.default.removeItem(at: surviveTmp)

print("CaffeinateController — hold TTL")
let ttlTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-ttl-\(UUID().uuidString).json")
let ttlController = CaffeinateController(store: StateStore(url: ttlTmp))
do {
    _ = try ttlController.hold("ephemeral", ttl: 1)
    check(ttlController.status().phase() == .heldBy(count: 1), "TTL hold is live before expiry")
    usleep(1_300_000)
    let expired = ttlController.status()
    check(expired.phase() == .off && expired.holders.isEmpty && expired.pid == nil,
          "expired TTL hold is pruned and caffeinate stopped")
} catch {
    check(false, "TTL hold threw: \(error)")
}
try? FileManager.default.removeItem(at: ttlTmp)

print("CaffeinateController — concurrent holds/releases")
let concTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tamp-conc-\(UUID().uuidString).json")
let concIterations = 12
DispatchQueue.concurrentPerform(iterations: concIterations) { @Sendable i in
    _ = try? CaffeinateController(store: StateStore(url: concTmp)).hold("conc-\(i)")
}
let concController = CaffeinateController(store: StateStore(url: concTmp))
let afterHolds = concController.status()
check(afterHolds.liveHolders().count == concIterations,
      "\(concIterations) concurrent holds all recorded (no lost updates)")
let concPid = afterHolds.pid
check(concPid.map { kill($0, 0) == 0 } == true, "one shared caffeinate is live after concurrent holds")
DispatchQueue.concurrentPerform(iterations: concIterations) { @Sendable i in
    _ = try? CaffeinateController(store: StateStore(url: concTmp)).release("conc-\(i)")
}
let afterReleases = concController.status()
check(afterReleases.holders.isEmpty && afterReleases.pid == nil,
      "concurrent releases drain to zero and clear the pid")
if let pid = concPid {
    var gone = false
    for _ in 0..<50 {
        if kill(pid, 0) != 0 { gone = true; break }
        usleep(20_000)
    }
    check(gone, "shared caffeinate is gone after the last concurrent release")
}
try? FileManager.default.removeItem(at: concTmp)

print("")
if failures == 0 {
    print("All checks passed.")
} else {
    print("\(failures) check(s) FAILED.")
    exit(1)
}
