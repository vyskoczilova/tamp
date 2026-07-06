import os

/// Engine-level logger. TampKit has no UI to surface failures in, so
/// problems the front-ends can't reasonably present (state-file writes,
/// coordination errors) are at least visible in Console / `log stream`.
let kitLog = Logger(subsystem: Preferences.suiteName, category: "TampKit")
