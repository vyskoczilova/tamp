import AppKit
import CoffeeKit
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
        let phase = state.phase(systemActive: SystemAssertions.isCaffeinated())
        updateIcon(phase: phase)
        rescheduleExpiryPoll(for: state)
    }

    private func updateIcon(phase: CoffeeState.Phase) {
        let style = preferences.iconStyle
        let isActive = phase != .off
        let symbol = isActive ? style.activeSymbol : style.inactiveSymbol
        let description = isActive ? "Caffeinated" : "Decaffeinated"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: description)
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    /// Schedule a background poll whenever the icon can change without a file-
    /// system event: timed sessions (expiry) and Coffee-inactive periods
    /// (external caffeinate start/stop). Uses a short interval when inactive so
    /// the icon tracks external processes in near-real-time.
    private func rescheduleExpiryPoll(for state: CoffeeState) {
        let interval: TimeInterval? =
            state.active && state.endsAt != nil ? 30 :   // timed session expiry
            !state.active                       ? 5  :   // external caffeinate detection
            nil                                           // indefinite own session — no poll needed
        if let interval {
            if refreshTimer == nil || refreshTimer?.timeInterval != interval {
                refreshTimer?.invalidate()
                refreshTimer = Timer.scheduledTimer(
                    timeInterval: interval, target: self, selector: #selector(refreshTick),
                    userInfo: nil, repeats: true
                )
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
        menu.addItem(iconSubmenu())
        menu.addItem(preventSubmenu())
        menu.addItem(loginItemMenuItem())

        menu.addItem(.separator())
        let version = NSMenuItem(title: "Version \(appVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        let quit = NSMenuItem(title: "Quit Coffee", action: #selector(quitTapped), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func statusLine(phase: CoffeeState.Phase, state: CoffeeState) -> NSMenuItem {
        let title: String
        switch phase {
        case .off:
            title = "Off — Mac can sleep"
        case .onTimed(let remaining):
            title = "On — \(DurationParser.format(remaining: remaining)) left"
        case .onIndefinite:
            title = "On — until turned off"
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

    private func iconSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Icon Style", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let current = preferences.iconStyle
        for style in IconStyle.allCases {
            let item = NSMenuItem(title: style.label, action: #selector(iconTapped(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = style == current ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func preventSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Prevent Sleep Of", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let flags = preferences.sleepFlags
        for (index, toggle) in SleepFlags.toggles.enumerated() {
            let item = NSMenuItem(title: toggle.label, action: #selector(preventTapped(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = flags[keyPath: toggle.keyPath] ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func loginItemMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Launch at Login", action: #selector(loginItemTapped), keyEquivalent: "")
        item.target = self
        if LoginItem.isBundledApp {
            item.state = LoginItem.isEnabled ? .on : .off
        } else {
            item.isEnabled = false
            item.toolTip = "Available when running the packaged Coffee.app"
        }
        return item
    }

    // MARK: - Actions

    @objc private func toggleTapped() {
        do { try controller.toggle() } catch { logError(error) }
        refresh()
    }

    @objc private func durationTapped(_ sender: NSMenuItem) {
        let preset = durationPresets[sender.tag]
        do { try controller.start(duration: preset.seconds) } catch { logError(error) }
        refresh()
    }

    @objc private func iconTapped(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let style = IconStyle(rawValue: raw) {
            preferences.iconStyle = style
        }
        refresh()
    }

    @objc private func preventTapped(_ sender: NSMenuItem) {
        var flags = preferences.sleepFlags
        flags[keyPath: SleepFlags.toggles[sender.tag].keyPath].toggle()
        // The engine persists the flags and restarts a live session for us.
        do { try controller.applyFlags(flags) } catch { logError(error) }
        refresh()
    }

    @objc private func loginItemTapped() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            logError(error)
        }
        refresh()
    }

    @objc private func quitTapped() {
        NSApp.terminate(nil)
    }

    private func logError(_ error: Error) {
        NSLog("Coffee: caffeinate action failed — %@", String(describing: error))
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
