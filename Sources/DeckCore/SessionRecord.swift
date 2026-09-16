import Foundation

/// One entry of Claude Code's live-session registry (`~/.claude/sessions/<pid>.json`).
public struct SessionRecord: Codable, Equatable, Sendable {
    public var pid: Int32
    public var sessionId: String
    public var cwd: String
    public var startedAt: Double?
    public var updatedAt: Double?
    public var procStart: String?
    public var version: String?
    public var kind: String?
    public var entrypoint: String?
    public var name: String?
    public var nameSource: String?
    public var status: String?
    public var statusUpdatedAt: Double?

    public init(
        pid: Int32, sessionId: String, cwd: String,
        startedAt: Double? = nil, updatedAt: Double? = nil, procStart: String? = nil,
        version: String? = nil, kind: String? = nil, entrypoint: String? = nil,
        name: String? = nil, nameSource: String? = nil, status: String? = nil, statusUpdatedAt: Double? = nil
    ) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.procStart = procStart
        self.version = version
        self.kind = kind
        self.entrypoint = entrypoint
        self.name = name
        self.nameSource = nameSource
        self.status = status
        self.statusUpdatedAt = statusUpdatedAt
    }

    public var procStartDate: Date? { procStart.flatMap { Self.parseProcStart($0) } }

    public var updatedDate: Date? { updatedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    public var startedDate: Date? { startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    public var statusDate: Date? { statusUpdatedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }

    /// Claude writes `procStart` ctime-style in UTC, e.g. "Sun Aug 30 07:19:16 2026".
    public static func parseProcStart(_ raw: String, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> Date? {
        let collapsed = raw.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        return ProcStartFormatters.shared.date(from: collapsed, timeZone: timeZone)
    }
}

/// DateFormatter creation is expensive (ICU); the poll parses every session each tick.
private final class ProcStartFormatters: @unchecked Sendable {
    static let shared = ProcStartFormatters()
    private let lock = NSLock()
    private var byZone: [String: DateFormatter] = [:]

    func date(from string: String, timeZone: TimeZone) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        let formatter = byZone[timeZone.identifier] ?? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
            byZone[timeZone.identifier] = formatter
            return formatter
        }()
        return formatter.date(from: string)
    }
}
