import Foundation

/// Single logging point for a failed engine action in the menu bar app. Both the
/// menu (`AppDelegate`) and the settings panel route here so the format stays
/// consistent instead of each front-end re-spelling the same `NSLog`.
func logCoffeeError(_ context: String, _ error: Error) {
    NSLog("Coffee: %@ — %@", context, String(describing: error))
}
