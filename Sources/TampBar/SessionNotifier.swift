import AppKit
import TampKit
import UserNotifications

/// Schedules the opt-in "session ended" notification. Instead of watching the
/// clock, a single pending request (fixed identifier) is keyed to the session's
/// `endsAt` and reconciled on every refresh — extend reschedules it, stop and
/// replace remove it, and re-adding with the same identifier atomically
/// overwrites. The notification daemon delivers it even while the menu is
/// closed, and sessions started from the CLI are covered because refreshes are
/// driven by the state-file watcher.
@MainActor
final class SessionNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let requestIdentifier = "cz.kybernaut.tamp.sessionEnd"

    /// `UNUserNotificationCenter` requires a bundle identifier — the bare
    /// SwiftPM binary has none, so the feature only exists in the packaged app
    /// (mirrors `LoginItem.isBundledApp`).
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    private let preferences: Preferences
    private var scheduledEnd: Date?

    init(preferences: Preferences) {
        self.preferences = preferences
        super.init()
        guard Self.isAvailable else { return }
        // Without a delegate answering `willPresent`, macOS suppresses
        // notifications from a running app — and TampBar is always running.
        UNUserNotificationCenter.current().delegate = self
    }

    /// Reconcile the pending request with the current state.
    func sync(with state: TampState) {
        guard Self.isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        guard preferences.notifyOnSessionEnd,
              state.active,
              let endsAt = state.endsAt,
              endsAt.timeIntervalSinceNow > 1
        else {
            scheduledEnd = nil
            center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
            return
        }
        guard endsAt != scheduledEnd else { return }
        scheduledEnd = endsAt

        let content = UNMutableNotificationContent()
        content.title = "Keep-awake ended"
        content.body = "The Tamp session finished — your Mac can sleep again."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: endsAt.timeIntervalSinceNow, repeats: false
        )
        center.add(UNNotificationRequest(
            identifier: Self.requestIdentifier, content: content, trigger: trigger
        ))
    }

    /// Ask the system for permission (used when the user enables the setting).
    /// The prompt is only shown once per app; later denials must be undone in
    /// System Settings.
    static func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
