import AppKit
import CoffeeKit

// Headless teardown hook used by Scripts/uninstall.sh. Must run from inside the
// .app bundle so `SMAppService.mainApp` resolves to this app's login-item
// registration. Unregisters and exits without ever showing a menu bar icon.
if CommandLine.arguments.contains("--unregister-login") {
    try? LoginItem.setEnabled(false)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory: live in the menu bar with no Dock icon, no main menu.
app.setActivationPolicy(.accessory)
app.run()
