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

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var refreshTimer: Timer?
    private var settingsWindowController: SettingsWindowController?

    private let durationPresets: [(label: String, seconds: Int)] = [
        ("30 minutes", 30 * 60),
        ("1 hour", 60 * 60),
        ("2 hours", 2 * 60 * 60),
        ("5 hours", 5 * 60 * 60),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        // The menu is rebuilt lazily when it's about to open (see
        // `menuNeedsUpdate`), so nothing reconstructs it while it's closed.
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        startWatchingState()
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
        let phase = state.phase(externalSources: externalSources(for: state))
        updateIcon(phase: phase)
        rescheduleExpiryPoll(for: state)
    }

    /// External caffeinate scan, skipped while Tamp's own session is live —
    /// `phase` ignores external sources then, so the scan would be wasted.
    private func externalSources(for state: TampState) -> [ExternalCaffeination] {
        state.active ? [] : SystemAssertions.externalCaffeinations()
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
        let phase = state.phase(externalSources: externalSources(for: state))
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

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsTapped), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let version = NSMenuItem(title: "Version \(appVersion)", action: #selector(versionTapped), keyEquivalent: "")
        version.target = self
        version.toolTip = "Open the release notes on GitHub"
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
            title = "On — \(DurationParser.format(remaining: remaining)) left"
        case .onIndefinite:
            title = "On — until turned off"
        case .externallyActive(let sources):
            title = "On — caffeinated by \(sources.sourceSummary ?? "another app")"
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

    @objc private func versionTapped() {
        NSWorkspace.shared.open(appReleaseURL())
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
        let fd = open(store.url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            // Delivered on the main queue, so it is safe to assume isolation.
            MainActor.assumeIsolated {
                guard let self else { return }
                // Atomic writes replace the inode, so re-arm the watch.
                self.fileWatcher?.cancel()
                self.startWatchingState()
                self.refresh()
            }
        }
        source.setCancelHandler { close(fd) }
        fileWatcher = source
        source.resume()
    }
}
