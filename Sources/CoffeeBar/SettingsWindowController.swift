import AppKit
import CoffeeKit

/// Settings panel: sleep flags, icon style, and launch-at-login. These used to
/// live in the menu itself; pulling them out keeps the menu to actions only.
///
/// The controls read live from `Preferences`/`LoginItem` each time the window is
/// shown, so the panel always reflects current state even if the CLI changed it.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let preferences: Preferences
    private let controller: CaffeinateController
    private let onChange: () -> Void

    private var sleepChecks: [NSButton] = []
    private var iconPopUp: NSPopUpButton!
    private var iconPreview: NSImageView!
    private var loginCheck: NSButton!

    init(preferences: Preferences, controller: CaffeinateController, onChange: @escaping () -> Void) {
        self.preferences = preferences
        self.controller = controller
        self.onChange = onChange

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 0),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Coffee Settings"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        super.init(window: panel)
        panel.contentView = buildContentView()
        panel.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Bring the panel forward, syncing every control to current state first.
    func present() {
        syncControls()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func buildContentView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(header("General"))
        loginCheck = checkbox(title: "Launch at Login", action: #selector(loginToggled))
        stack.addArrangedSubview(loginCheck)
        stack.addArrangedSubview(spacer())

        stack.addArrangedSubview(header("Prevent Sleep Of"))
        for toggle in SleepFlags.toggles {
            let (row, check) = flagRow(title: toggle.label, detail: toggle.detail,
                                       action: #selector(sleepFlagTapped(_:)))
            sleepChecks.append(check)
            stack.addArrangedSubview(row)
        }

        stack.addArrangedSubview(spacer())
        stack.addArrangedSubview(header("Icon"))
        iconPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        iconPopUp.target = self
        iconPopUp.action = #selector(iconChanged)
        // Item order matches IconStyle.allCases, so selection maps by index
        // (see syncControls / iconChanged) — no per-item representedObject needed.
        for style in IconStyle.allCases {
            iconPopUp.addItem(withTitle: style.label)
        }
        iconPreview = NSImageView()
        iconPreview.contentTintColor = .labelColor
        iconPreview.widthAnchor.constraint(equalToConstant: 22).isActive = true
        iconPreview.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let iconRow = NSStackView(views: [iconPopUp, iconPreview])
        iconRow.orientation = .horizontal
        iconRow.spacing = 10
        stack.addArrangedSubview(iconRow)

        stack.addArrangedSubview(spacer())
        let divider = NSBox()
        divider.boxType = .separator
        divider.widthAnchor.constraint(equalToConstant: 320).isActive = true
        stack.addArrangedSubview(divider)
        stack.addArrangedSubview(footer(copyrightText()))

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }

    private func header(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func checkbox(title: String, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        return button
    }

    /// A checkbox with a dim one-line description beneath it.
    private func flagRow(title: String, detail: String, action: Selector) -> (row: NSView, checkbox: NSButton) {
        let check = checkbox(title: title, action: action)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailLabel.textColor = .secondaryLabelColor
        let column = NSStackView(views: [check, detailLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 1
        return (column, check)
    }

    private func footer(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: 4).isActive = true
        return view
    }

    /// The copyright string the bundle advertises (set by make-app.sh), falling
    /// back to a literal when running the bare binary (no Info.plist).
    private func copyrightText() -> String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "© 2026 Karolína Vyskočilová"
    }

    /// A template image of the style's active artwork for the preview.
    private func iconImage(for style: IconStyle) -> NSImage? {
        IconRenderer.image(for: style, active: true, pointSize: 18)
    }

    // MARK: - Sync

    /// Push current persisted state into the controls.
    private func syncControls() {
        let flags = preferences.sleepFlags
        for (check, toggle) in zip(sleepChecks, SleepFlags.toggles) {
            check.state = flags[keyPath: toggle.keyPath] ? .on : .off
        }
        let current = preferences.iconStyle
        iconPopUp.selectItem(at: IconStyle.allCases.firstIndex(of: current) ?? 0)
        iconPreview.image = iconImage(for: current)
        if LoginItem.isBundledApp {
            loginCheck.isEnabled = true
            loginCheck.state = LoginItem.isEnabled ? .on : .off
            loginCheck.toolTip = nil
        } else {
            loginCheck.isEnabled = false
            loginCheck.state = .off
            loginCheck.toolTip = "Available when running the packaged Coffee.app"
        }
    }

    // MARK: - Actions

    @objc private func sleepFlagTapped(_ sender: NSButton) {
        guard let index = sleepChecks.firstIndex(of: sender) else { return }
        var flags = preferences.sleepFlags
        flags[keyPath: SleepFlags.toggles[index].keyPath] = sender.state == .on
        // The engine persists the flags and restarts a live session for us.
        do { try controller.applyFlags(flags) } catch { logCoffeeError("settings action failed", error) }
        onChange()
    }

    @objc private func iconChanged() {
        let index = iconPopUp.indexOfSelectedItem
        if IconStyle.allCases.indices.contains(index) {
            let style = IconStyle.allCases[index]
            preferences.iconStyle = style
            iconPreview.image = iconImage(for: style)
        }
        onChange()
    }

    @objc private func loginToggled() {
        do {
            try LoginItem.setEnabled(loginCheck.state == .on)
        } catch {
            logCoffeeError("settings action failed", error)
            syncControls()
        }
        onChange()
    }
}
