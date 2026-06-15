import AppKit
import CoffeeKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory: live in the menu bar with no Dock icon, no main menu.
app.setActivationPolicy(.accessory)
app.run()
