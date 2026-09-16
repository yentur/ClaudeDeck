import AppKit

/// Version, project links and bundle-location facts. Opening a link never makes a network
/// request from ClaudeDeck itself; it just hands the URL to the default browser.
enum AppInfo {
    static let repositoryURL = URL(string: "https://github.com/yentur/ClaudeDeck")!
    static let latestReleaseURL = URL(string: "https://github.com/yentur/ClaudeDeck/releases/latest")!

    /// `CFBundleShortVersionString`, or "dev" when running outside an app bundle (`swift run`).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// Gatekeeper runs quarantined apps that were never moved from their download location from a
    /// randomized read-only path. Such a path disappears later, so nothing should point at it.
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
