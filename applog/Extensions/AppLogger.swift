import Foundation
import os

/// Unified-logging categories, one per subsystem area. Prefer these over
/// `print` so error output is visible in Console.app / `log show` on a
/// shipped build, not just when attached to a debugger.
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.apptracker.AppTracker"

    static let environment = Logger(subsystem: subsystem, category: "AppEnvironment")
    static let tracking = Logger(subsystem: subsystem, category: "TrackingEngine")
    static let settings = Logger(subsystem: subsystem, category: "Settings")
    static let statistics = Logger(subsystem: subsystem, category: "Statistics")
}
