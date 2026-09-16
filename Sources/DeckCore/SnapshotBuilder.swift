import Foundation

public enum SessionActivity: Equatable, Hashable, Sendable {
    case busy, idle, shell
    case other(String)

    public init(status: String?) {
        switch status {
        case "busy": self = .busy
        case "idle", nil: self = .idle
        case "shell": self = .shell
        case let value?: self = .other(value)
        }
    }

    var sortRank: Int {
        switch self {
        case .busy: return 0
        case .shell, .other: return 1
        case .idle: return 2
        }
    }
}

public struct LiveSession: Identifiable, Equatable, Sendable {
    public var id: String { sessionId }
    public var pid: Int32
    public var sessionId: String
    public var cwd: String
    public var title: String
    public var activity: SessionActivity
    public var updatedAt: Date?
    public var flags: [String]
    /// The session process's terminal-related environment (`HostResolver.envKeys`).
    public var terminalEnv: [String: String]
    /// The terminal app (and tty / tmux pane) the session runs in.
    public var host: SessionHost
    /// "cli" for terminal sessions; SDK-driven sessions report e.g. "sdk-py".
    public var entrypoint: String?
    public var usage: ResourceUsage?
    public var startedAt: Date?
    /// When the current `activity` began.
    public var statusSince: Date?
    public var lastPrompt: String?
    public var model: String?
    public var permissionMode: String?
    public var transcriptBytes: UInt64?

    public init(pid: Int32, sessionId: String, cwd: String, title: String, activity: SessionActivity,
                updatedAt: Date? = nil, flags: [String] = [], terminalEnv: [String: String] = [:],
                host: SessionHost = .unknown, entrypoint: String? = nil,
                usage: ResourceUsage? = nil, startedAt: Date? = nil, statusSince: Date? = nil, lastPrompt: String? = nil,
                model: String? = nil, permissionMode: String? = nil, transcriptBytes: UInt64? = nil) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        self.title = title
        self.activity = activity
        self.updatedAt = updatedAt
        self.flags = flags
        self.terminalEnv = terminalEnv
        self.host = host
        self.entrypoint = entrypoint
        self.usage = usage
        self.startedAt = startedAt
        self.statusSince = statusSince
        self.lastPrompt = lastPrompt
        self.model = model
        self.permissionMode = permissionMode
        self.transcriptBytes = transcriptBytes
    }

    public var isWorking: Bool { activity == .busy || activity == .shell }

    /// Controlling terminal of the session process, e.g. "/dev/ttys003".
    public var tty: String? { host.tty }

    /// The cmux subset of `terminalEnv` (what sleep records keep).
    public var cmuxEnv: [String: String] { terminalEnv.filter { CmuxFocus.envKeys.contains($0.key) } }
}

public struct SnapshotBuilder: Sendable {
    public let paths: DeckPaths
    public let inspector: ProcessInspecting
    public let transcripts: TranscriptCache
    public let sampler: ResourceSampler

    public init(paths: DeckPaths, inspector: ProcessInspecting, transcripts: TranscriptCache, sampler: ResourceSampler) {
        self.paths = paths
        self.inspector = inspector
        self.transcripts = transcripts
        self.sampler = sampler
    }

    /// proc_pidpath fails once an executable was replaced on disk (e.g. an app updated while it
    /// runs); KERN_PROCARGS2 still has the original path for the user's own processes.
    private func hostExecutablePath(_ pid: Int32) -> String? {
        inspector.executablePath(pid) ?? inspector.args(pid)?.executablePath
    }

    public func build() -> [LiveSession] {
        let live = RegistryReader.read(dir: paths.sessionsDir)
            .filter { Liveness.isLiveClaude($0, inspector: inspector) }

        var newest: [String: SessionRecord] = [:]
        for record in live {
            if let existing = newest[record.sessionId], (existing.updatedAt ?? 0) >= (record.updatedAt ?? 0) {
                continue
            }
            newest[record.sessionId] = record
        }
        let table = inspector.processTable()
        let usage = sampler.sample(roots: newest.values.map(\.pid), inspector: inspector, table: table)
        let parents = ProcessParents(table)

        return newest.values.map { record in
            let args = inspector.args(record.pid)
            let env = args?.env ?? [:]
            let transcript = transcripts.info(for: record, projectsDir: paths.projectsDir)
            let host = HostResolver.resolve(pid: record.pid, env: env, parents: parents, tty: inspector.ttyPath(record.pid),
                                            executablePath: hostExecutablePath)
            return LiveSession(
                pid: record.pid,
                sessionId: record.sessionId,
                cwd: record.cwd,
                title: TitleResolver.resolve(record, aiTitle: transcript?.aiTitle),
                activity: SessionActivity(status: record.status),
                updatedAt: record.updatedDate,
                flags: ResumeCommand.preservedFlags(from: args?.argv ?? []),
                terminalEnv: env.filter { HostResolver.envKeys.contains($0.key) },
                host: host,
                entrypoint: record.entrypoint,
                usage: usage[record.pid],
                startedAt: record.startedDate,
                statusSince: record.statusDate,
                lastPrompt: transcript?.lastPrompt,
                model: transcript?.model,
                permissionMode: transcript?.permissionMode,
                transcriptBytes: transcript?.sizeBytes
            )
        }
        .sorted { a, b in
            if a.activity.sortRank != b.activity.sortRank { return a.activity.sortRank < b.activity.sortRank }
            return (a.updatedAt ?? .distantPast) > (b.updatedAt ?? .distantPast)
        }
    }
}
