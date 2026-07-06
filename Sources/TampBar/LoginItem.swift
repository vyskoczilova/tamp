import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` so the app can register/unregister itself as a
/// macOS login item — the modern, LaunchAgent-free way to launch at login.
///
/// This only works when running from a real `.app` bundle (Launch Services
/// needs a registered application to launch). When running the bare SwiftPM
/// binary, `isBundledApp` is false and the menu disables the toggle.
enum LoginItem {

    /// True when the running executable lives inside an `.app` bundle.
    static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register or unregister the app as a login item.
    /// Throws if the system rejects the change (e.g. when not bundled).
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
