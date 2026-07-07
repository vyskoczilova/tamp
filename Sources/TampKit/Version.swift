import Foundation

/// Single source of truth for the app version. Bump alongside the VERSION file.
public let appVersion = "1.1.0"

/// Canonical project home — where version links in the UIs point.
public let appRepoURL = URL(string: "https://github.com/vyskoczilova/tamp")!

/// Release-notes page for a version tag (defaults to the running version).
public func appReleaseURL(for version: String = appVersion) -> URL {
    appRepoURL.appendingPathComponent("releases/tag/v\(version)")
}
