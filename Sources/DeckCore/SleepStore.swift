import Foundation

/// A session that was closed via "Uyut" and can be resumed later.
public struct SleepingSession: Codable, Identifiable, Equatable, Sendable {
    public var id: String { sessionId }
    public var sessionId: String
    public var cwd: String
    public var title: String
    public var flags: [String]
    public var sleptAt: Date
    public var cmuxEnv: [String: String]?
    /// Bundle id of the terminal the session ran in (absent in records from older versions).
    public var hostBundleID: String?

    public init(sessionId: String, cwd: String, title: String, flags: [String], sleptAt: Date, cmuxEnv: [String: String]?,
                hostBundleID: String? = nil) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.title = title
        self.flags = flags
        self.sleptAt = sleptAt
        self.cmuxEnv = cmuxEnv
        self.hostBundleID = hostBundleID
    }

    /// The terminal to reopen it in: the recorded host, or cmux for older records made inside cmux.
    public var resumeHostBundleID: String? {
        hostBundleID ?? (cmuxEnv.flatMap(CmuxFocus.workspaceId(env:)) != nil ? TerminalKind.cmux.bundleIDs.first : nil)
    }
}

public final class SleepStore: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
    }

    public func load() -> [SleepingSession] {
        lock.lock()
        defer { lock.unlock() }
        return unlockedLoad()
    }

    public func save(_ sessions: [SleepingSession]) throws {
        lock.lock()
        defer { lock.unlock() }
        try unlockedSave(sessions)
    }

    /// Inserts or replaces (moving it to the end) the entry with the same session id.
    public func upsert(_ session: SleepingSession) throws {
        lock.lock()
        defer { lock.unlock() }
        var all = unlockedLoad().filter { $0.sessionId != session.sessionId }
        all.append(session)
        try unlockedSave(all)
    }

    public func remove(sessionId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let all = unlockedLoad()
        let kept = all.filter { $0.sessionId != sessionId }
        guard kept.count != all.count else { return }
        try unlockedSave(kept)
    }

    private func unlockedLoad() -> [SleepingSession] {
        guard let data = FileManager.default.contents(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SleepingSession].self, from: data)) ?? []
    }

    private func unlockedSave(_ sessions: [SleepingSession]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(sessions).write(to: url, options: .atomic)
    }
}
