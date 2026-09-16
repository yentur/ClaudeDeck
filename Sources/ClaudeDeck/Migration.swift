import AppKit

/// One-time upgrade from pre-release builds that used the bundle id `com.omer.claudedeck`:
/// carries preferences over, re-points the login item and quits a still-running old copy.
enum LegacyMigration {
    static let legacyBundleID = "com.omer.claudedeck"
    private static let doneKey = "migratedFromLegacyBundleID"

    @MainActor
    static func run(env: [String: String] = ProcessInfo.processInfo.environment) {
        // Dev runs use an isolated defaults suite; never touch real preferences from them.
        guard env["CLAUDE_DECK_DEFAULTS_SUITE"] == nil, Bundle.main.bundleIdentifier != legacyBundleID else { return }

        for app in NSRunningApplication.runningApplications(withBundleIdentifier: legacyBundleID) {
            app.terminate()
        }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: doneKey) {
            if let legacy = defaults.persistentDomain(forName: legacyBundleID) {
                for (key, value) in legacy where defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                }
            }
            defaults.set(true, forKey: doneKey)
        }

        let legacyAgent = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(legacyBundleID).plist")
        if FileManager.default.fileExists(atPath: legacyAgent.path) {
            try? FileManager.default.removeItem(at: legacyAgent)
            try? LoginItem.setEnabled(true)
        }
    }
}
