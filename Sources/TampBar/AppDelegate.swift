import AppKit
import TampKit
import Foundation

/// The menu bar controller. Owns the status item, reflects the shared state in
/// its icon, and drives the engine from menu actions. It watches the state file
/// so changes made from the CLI show up here too.
///
/// The whole class is `@MainActor`: it lives entirely on the main thread and
/// only touches AppKit, which is main-actor-isolated.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let controller = CaffeinateController()
    private let preferences = Preferences()
    private let store = StateStore()
    private let scheduleStore = ScheduleStore()

    private var stateWatcher: FileWatcher?
    private var refreshTimer: Timer?
    private var settingsWindowController: SettingsWindowController?
    private var notifier: SessionNotifier?
    private var scheduleRunner: ScheduleRunner?

    private let durationPresets: [(label: String, seconds: Int)] = [
        ("30 minutes", 30 * 60),
        ("1 hour", 60 * 60),
        ("2 hours", 2 * 60 * 60),
        ("5 hours", 5 * 60 * 60),
    ]

    private let extendPresets: [(label: String, seconds: Int)] = [
        ("+15 minutes", 15 * 60),
        ("+30 minutes", 30 * 60),
        ("+1 hour", 60 * 60),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifier = SessionNotifier(preferences: preferences)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        // The menu is rebuilt lazily when it's about to open (see
        // `menuNeedsUpdate`), so nothing reconstructs it while it's closed.
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        startWatchingState()
        scheduleRunner = ScheduleRunner(controller: controller, store: scheduleStore) { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    @objc private func refreshTick() {
        refresh()
    }

    // MARK: - Rendering

    /// Update everything that's visible while the menu is *closed* (just the
    /// icon) and keep the expiry poll in sync. The menu itself is rebuilt on
    /// open, so it isn't touched here.
    private func refresh() {
        let state = controller.status()
        let phase = state.phase(systemActive: SystemAssertions.isCaffeinated())
        updateIcon(phase: phase)
        rescheduleExpiryPoll(for: state)
        notifier?.sync(with: state)
    }

    private func updateIcon(phase: TampState.Phase) {
        let isActive = phase != .off
        statusItem.button?.image = IconRenderer.image(
            for: preferences.iconStyle, active: isActive, pointSize: 18
        )
    }

    /// Schedule a background poll whenever the icon can change without a file-
    /// system event: timed sessions (expiry) and Tamp-inactive periods
    /// (external caffeinate start/stop). Uses a short interval when inactive so
    /// the icon tracks external processes in near-real-time.
    private func rescheduleExpiryPoll(for state: TampState) {
        let interval: TimeInterval? =
            state.active && state.watchedPID != nil ? 5 :  // while-app end (caffeinate exits, no file event)
            state.active && state.endsAt != nil ? 30 :   // timed session expiry
            !state.active                       ? 5  :   // external caffeinate detection
            nil                                           // indefinite own session — no poll needed
        if let interval {
            if refreshTimer == nil || refreshTimer?.timeInterval != interval {
                refreshTimer?.invalidate()
                let timer = Timer.scheduledTimer(
                    timeInterval: interval, target: self, selector: #selector(refreshTick),
                    userInfo: nil, repeats: true
                )
                // Nothing here is deadline-critical — let the system coalesce
                // wakeups instead of firing on the exact tick (battery).
                timer.tolerance = min(2, interval * 0.2)
                refreshTimer = timer
            }
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    // MARK: - Menu (rebuilt on demand)

    func menuNeedsUpdate(_ menu: NSMenu) {
        let state = controller.status()
        let phase = state.phase(systemActive: SystemAssertions.isCaffeinated())
        menu.removeAllItems()
        updateIcon(phase: phase)

        menu.addItem(statusLine(phase: phase, state: state))
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: state.active ? "Turn Off" : "Keep Awake",
            action: #selector(toggleTapped),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(durationSubmenu())
        menu.addItem(whileAppSubmenu())
        menu.addItem(schedulesSubmenu())
        if case .onTimed = phase {
            menu.addItem(extendSubmenu())
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsTapped), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let version = NSMenuItem(title: "Version \(appVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        let quit = NSMenuItem(title: "Quit Tamp", action: #selector(quitTapped), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func statusLine(phase: TampState.Phase, state: TampState) -> NSMenuItem {
        let title: String
        switch phase {
        case .off:
            title = "Off — Mac can sleep"
        case .onTimed(let remaining):
            let until = state.endsAt.map { " (until \(DurationParser.clock($0)))" } ?? ""
            title = "On — \(DurationParser.format(remaining: remaining)) left\(until)"
        case .onIndefinite:
            title = "On — until turned off"
        case .onWhileApp(let name):
            title = "On — while \(name) runs"
        case .externallyActive:
            title = "On — caffeinated by another app"
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func durationSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Keep Awake For", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (index, preset) in durationPresets.enumerated() {
            let item = NSMenuItem(title: preset.label, action: #selector(durationTapped(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let custom = NSMenuItem(title: "Custom…", action: #selector(customDurationTapped), keyEquivalent: "")
        custom.target = self
        submenu.addItem(custom)
        parent.submenu = submenu
        return parent
    }

    /// Snapshot of the apps listed in the "Keep Awake While…" submenu, so a
    /// tapped item's tag can be mapped back to a concrete process. Rebuilt on
    /// every menu open — the pid is captured here, and the session then follows
    /// that specific instance (quit + relaunch does not re-arm it).
    private var whileAppTargets: [(name: String, pid: pid_t)] = []

    private func whileAppSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Keep Awake While…", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        whileAppTargets = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.localizedName.map { (name: $0, pid: app.processIdentifier) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if whileAppTargets.isEmpty {
            let empty = NSMenuItem(title: "No Running Apps", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        for (index, target) in whileAppTargets.enumerated() {
            let item = NSMenuItem(title: target.name, action: #selector(whileAppTapped(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    @objc private func whileAppTapped(_ sender: NSMenuItem) {
        guard whileAppTargets.indices.contains(sender.tag) else { return }
        let target = whileAppTargets[sender.tag]
        do {
            try controller.startWhile(pid: target.pid, name: target.name)
        } catch {
            logTampError("caffeinate action failed", error)
        }
        refresh()
    }

    /// Snapshot of the schedules shown in the submenu, mapping item tags back
    /// to schedule ids. Rebuilt on every menu open.
    private var scheduleItems: [Schedule] = []

    private func schedulesSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Schedules", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        scheduleItems = scheduleStore.load()
        for (index, schedule) in scheduleItems.enumerated() {
            let item = NSMenuItem(
                title: schedule.displayText,
                action: #selector(scheduleToggled(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = schedule.enabled ? .on : .off
            submenu.addItem(item)
        }
        if !scheduleItems.isEmpty { submenu.addItem(.separator()) }
        let add = NSMenuItem(title: "Add Schedule…", action: #selector(addScheduleTapped), keyEquivalent: "")
        add.target = self
        submenu.addItem(add)
        if !scheduleItems.isEmpty {
            let removeParent = NSMenuItem(title: "Remove", action: nil, keyEquivalent: "")
            let removeMenu = NSMenu()
            for (index, schedule) in scheduleItems.enumerated() {
                let item = NSMenuItem(
                    title: schedule.displayText,
                    action: #selector(scheduleRemoveTapped(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                removeMenu.addItem(item)
            }
            removeParent.submenu = removeMenu
            submenu.addItem(removeParent)
        }
        parent.submenu = submenu
        return parent
    }

    /// Checkmark = enabled; clicking flips it. Disabling stops future firings
    /// only — a session the schedule already started is ended via Turn Off.
    @objc private func scheduleToggled(_ sender: NSMenuItem) {
        guard scheduleItems.indices.contains(sender.tag) else { return }
        var schedules = scheduleStore.load()
        guard let index = schedules.firstIndex(where: { $0.id == scheduleItems[sender.tag].id }) else { return }
        schedules[index].enabled.toggle()
        scheduleStore.save(schedules) // the file watcher re-arms the runner
        refresh()
    }

    @objc private func scheduleRemoveTapped(_ sender: NSMenuItem) {
        guard scheduleItems.indices.contains(sender.tag) else { return }
        var schedules = scheduleStore.load()
        schedules.removeAll { $0.id == scheduleItems[sender.tag].id }
        scheduleStore.save(schedules)
        refresh()
    }

    @objc private func addScheduleTapped() {
        let alert = NSAlert()
        alert.messageText = "Add Schedule"
        alert.informativeText = "Examples: weekdays 9-17, daily 8:30-18, mon,wed,fri 9am-5pm"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "e.g. weekdays 9-17"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let schedule = try ScheduleParser.parse(field.stringValue)
            var schedules = scheduleStore.load()
            schedules.append(schedule)
            scheduleStore.save(schedules)
            refresh()
        } catch {
            let err = NSAlert()
            err.messageText = "Invalid schedule"
            err.informativeText = String(describing: error)
            err.runModal()
        }
    }

    private func extendSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Extend", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (index, preset) in extendPresets.enumerated() {
            let item = NSMenuItem(title: preset.label, action: #selector(extendTapped(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let custom = NSMenuItem(title: "Custom…", action: #selector(customExtendTapped), keyEquivalent: "")
        custom.target = self
        submenu.addItem(custom)
        parent.submenu = submenu
        return parent
    }

    @objc private func customExtendTapped() {
        let alert = NSAlert()
        alert.messageText = "Extend Session"
        alert.informativeText = "Enter extra time: 15m, 1h, 1h30m"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "e.g. +15m"
        alert.accessoryView = field
        alert.addButton(withTitle: "Extend")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let input = field.stringValue.trimmingCharacters(in: .whitespaces)
        do {
            let seconds = try DurationParser.seconds(from: input)
            try controller.extend(by: seconds)
            refresh()
        } catch {
            let err = NSAlert()
            err.messageText = "Could not extend"
            err.informativeText = String(describing: error)
            err.runModal()
        }
    }

    @objc private func customDurationTapped() {
        let alert = NSAlert()
        alert.messageText = "Keep Awake For"
        alert.informativeText = "Enter a duration: 30m, 1h, 1h30m, 90s"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "e.g. 45m"
        alert.accessoryView = field
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let input = field.stringValue.trimmingCharacters(in: .whitespaces)
        do {
            let seconds = try DurationParser.seconds(from: input)
            try controller.start(duration: seconds)
            refresh()
        } catch {
            let err = NSAlert()
            err.messageText = "Invalid duration"
            err.informativeText = String(describing: error)
            err.runModal()
        }
    }

    // MARK: - Actions

    @objc private func toggleTapped() {
        do { try controller.toggle() } catch { logTampError("caffeinate action failed", error) }
        refresh()
    }

    @objc private func durationTapped(_ sender: NSMenuItem) {
        let preset = durationPresets[sender.tag]
        do { try controller.start(duration: preset.seconds) } catch { logTampError("caffeinate action failed", error) }
        refresh()
    }

    @objc private func extendTapped(_ sender: NSMenuItem) {
        let preset = extendPresets[sender.tag]
        do { try controller.extend(by: preset.seconds) } catch { logTampError("caffeinate action failed", error) }
        refresh()
    }

    @objc private func settingsTapped() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                preferences: preferences,
                controller: controller,
                onChange: { [weak self] in self?.refresh() }
            )
        }
        settingsWindowController?.present()
    }

    @objc private func quitTapped() {
        NSApp.terminate(nil)
    }

    // MARK: - State file watching

    private func startWatchingState() {
        // Ensure the file exists so we can open a descriptor to watch.
        if !FileManager.default.fileExists(atPath: store.url.path) {
            store.save(controller.status())
        }
        stateWatcher = FileWatcher(path: store.url.path) { [weak self] in
            self?.refresh()
        }
    }
}
