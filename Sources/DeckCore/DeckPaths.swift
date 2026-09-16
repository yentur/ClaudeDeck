import Foundation

/// Filesystem locations used by the app. Every path can be overridden through
/// environment variables so development and tests never touch real sessions.
public struct DeckPaths: Equatable, Sendable {
    public var sessionsDir: URL
    public var projectsDir: URL
    public var stateDir: URL
    public var claudeBin: String

    public init(
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        func dir(_ key: String, _ fallback: URL) -> URL {
            if let value = env[key], !value.isEmpty {
                return URL(fileURLWithPath: value, isDirectory: true)
            }
            return fallback
        }
        let claudeHome = home.appendingPathComponent(".claude", isDirectory: true)
        sessionsDir = dir("CLAUDE_DECK_SESSIONS_DIR", claudeHome.appendingPathComponent("sessions", isDirectory: true))
        projectsDir = dir("CLAUDE_DECK_PROJECTS_DIR", claudeHome.appendingPathComponent("projects", isDirectory: true))
        stateDir = dir(
            "CLAUDE_DECK_STATE_DIR",
            home.appendingPathComponent("Library/Application Support/ClaudeDeck", isDirectory: true)
        )
        claudeBin = env["CLAUDE_DECK_CLAUDE_BIN"].flatMap { $0.isEmpty ? nil : $0 } ?? "claude"
    }

    public var sleepStoreURL: URL { stateDir.appendingPathComponent("sleeping.json") }
    public var scriptsDir: URL { stateDir.appendingPathComponent("scripts", isDirectory: true) }
}
