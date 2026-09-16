import AppKit
import DeckCore
import UniformTypeIdentifiers

/// A terminal app to open a resumed session in.
struct ResumeTarget: Equatable {
    var kind: TerminalKind
    var appURL: URL
}

/// LaunchServices side of terminal support: which terminals are installed, where resumed sessions
/// go, and bringing a session's host app to the front.
enum TerminalApps {
    static func url(forBundleID bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func url(for kind: TerminalKind) -> URL? {
        kind.bundleIDs.lazy.compactMap(url(forBundleID:)).first
    }

    /// Installed terminals ClaudeDeck can open resumed sessions in, in `TerminalKind` order.
    static func installedResumable() -> [TerminalKind] {
        TerminalKind.allCases.filter { $0.canResume && url(for: $0) != nil }
    }

    /// The app macOS opens `.command` files with, if it's a terminal ClaudeDeck can drive.
    static func defaultScriptHandler() -> ResumeTarget? {
        guard let type = UTType("com.apple.terminal.shell-script"),
              let url = NSWorkspace.shared.urlForApplication(toOpen: type),
              let bundleID = AppBundles.bundleID(forAppPath: url.path),
              let kind = TerminalKind(bundleID: bundleID), kind.canResume
        else { return nil }
        return ResumeTarget(kind: kind, appURL: url)
    }

    /// "Auto": the terminal the session last ran in → the default `.command` handler → Terminal.
    static func autoTarget(hostBundleID: String?) -> ResumeTarget {
        if let hostBundleID, let kind = TerminalKind(bundleID: hostBundleID), kind.canResume,
           let url = url(forBundleID: hostBundleID) ?? url(for: kind) {
            return ResumeTarget(kind: kind, appURL: url)
        }
        return defaultScriptHandler() ?? ResumeTarget(kind: .terminalApp, appURL: ScriptLauncher.terminalAppURL)
    }

    /// Display name for a host, falling back to its app bundle's name for unrecognised apps.
    static func name(of host: SessionHost, unknown: String) -> String {
        host.kind != .unknown ? host.kind.displayName : host.appName ?? unknown
    }

    /// Brings the host's app to the front. False when nothing identifies the app.
    @MainActor @discardableResult
    static func activate(_ host: SessionHost) -> Bool {
        var appURL = host.appPath.map { URL(fileURLWithPath: $0) }
        if appURL == nil, let pid = host.appPid { appURL = NSRunningApplication(processIdentifier: pid)?.bundleURL }
        if appURL == nil, let bundleID = host.bundleID { appURL = url(forBundleID: bundleID) }
        if appURL == nil { appURL = url(for: host.kind) }
        guard let appURL else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        return true
    }
}
