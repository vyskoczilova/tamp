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
final class AppDelegate: NSObject, NSApplicationDelegate {
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
        startWatchingState()
        // Refresh the "time left" line periodically while active. Target/action
        // (rather than a closure) avoids capturing self in a @Sendable block.
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 30, target: self, selector: #selector(refreshTick),
            userInfo: nil, repeats: true
        )
        refresh()
    }

    @objc private func refreshTick() {
        refresh()
    }

    // MARK: - Rendering

    private func refresh() {
        let state = controller.status()
        updateIcon(for: state)
        rebuildMenu(for: state)
    }

    private func updateIcon(for state: CoffeeState) {
        let style = preferences.iconStyle
        let symbol = state.active ? style.activeSymbol : style.inactiveSymbol
        let description = state.active ? "Caffeinated" : "Decaffeinated"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: description)
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func rebuildMenu(for state: CoffeeState) {
        let menu = NSMenu()

        menu.addItem(statusLine(for: state))
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: state.active ? "Turn Off" : "Keep Awake",
            action: #selector(toggleTapped), keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(durationSubmenu())
        menu.addItem(iconSubmenu())
        menu.addItem(preventSubmenu())
        menu.addItem(loginItemMenuItem())

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Coffee", action: #selector(quitTapped), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func statusLine(for state: CoffeeState) -> NSMenuItem {
        let title: String
        if !state.active {
            title = "Off — Mac can sleep"
        } else if let remaining = state.remaining() {
            title = "On — \(DurationParser.format(remaining: remaining)) left"
        } else {
            title = "On — until turned off"
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
        parent.submenu = submenu
        return parent
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
        let rows: [(String, String, Bool)] = [
            ("display", "Display", flags.display),
            ("system", "System", flags.system),
            ("disk", "Disk", flags.disk),
        ]
        for (key, label, on) in rows {
            let item = NSMenuItem(title: label, action: #selector(preventTapped(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = on ? .on : .off
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
        guard let key = sender.representedObject as? String else { return }
        var flags = preferences.sleepFlags
        switch key {
        case "display": flags.display.toggle()
        case "system": flags.system.toggle()
        case "disk": flags.disk.toggle()
        default: break
        }
        preferences.sleepFlags = flags
        // If a session is active, restart it so the new flags take effect now.
        let state = controller.status()
        if state.active {
            let remaining = state.remaining().map { Int($0) }
            do { try controller.start(duration: remaining, flags: flags) } catch { logError(error) }
        }
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
