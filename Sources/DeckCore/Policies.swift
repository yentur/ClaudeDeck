import Foundation

public struct FinishedTurn: Sendable {
    public var session: LiveSession
    public var worked: TimeInterval
    public var sessionId: String { session.sessionId }
}

/// Detects sessions that just finished a turn: working (busy/shell) → not working,
/// after having worked for at least `minimumBusy` seconds.
public struct FinishDetector: Sendable {
    public var minimumBusy: TimeInterval
    private var workingSince: [String: Date] = [:]

    public init(minimumBusy: TimeInterval = 20) {
        self.minimumBusy = minimumBusy
    }

    public mutating func update(_ sessions: [LiveSession], now: Date = Date()) -> [FinishedTurn] {
        var finished: [FinishedTurn] = []
        var next: [String: Date] = [:]
        for session in sessions {
            if session.isWorking {
                next[session.sessionId] = workingSince[session.sessionId] ?? session.statusSince ?? now
            } else if let since = workingSince[session.sessionId] {
                let endedAt = max(session.statusSince ?? now, since)
                let worked = endedAt.timeIntervalSince(since)
                if worked >= minimumBusy { finished.append(FinishedTurn(session: session, worked: worked)) }
            }
        }
        // Sessions that vanished (closed) are forgotten rather than reported.
        workingSince = next
        return finished
    }
}

public struct WarningThresholds: Equatable, Sendable {
    public var memoryBytes: UInt64
    public var cpuPercent: Double
    public var cpuSustain: TimeInterval

    public init(memoryBytes: UInt64, cpuPercent: Double, cpuSustain: TimeInterval) {
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
        self.cpuSustain = cpuSustain
    }
}

public enum ResourceWarning: String, Hashable, Sendable {
    case memory, cpu
}

public struct RaisedWarning: Sendable {
    public var session: LiveSession
    public var warning: ResourceWarning
}

/// Memory over the limit warns immediately; CPU only after staying over the limit for `cpuSustain`.
public struct ResourceWarningEvaluator: Sendable {
    public var thresholds: WarningThresholds
    private var cpuHighSince: [String: Date] = [:]
    private var active: [String: Set<ResourceWarning>] = [:]

    public init(thresholds: WarningThresholds) {
        self.thresholds = thresholds
    }

    public mutating func update(_ sessions: [LiveSession], now: Date = Date())
        -> (active: [String: Set<ResourceWarning>], raised: [RaisedWarning]) {
        var nextActive: [String: Set<ResourceWarning>] = [:]
        var nextHighSince: [String: Date] = [:]
        var raised: [RaisedWarning] = []

        for session in sessions {
            guard let usage = session.usage else { continue }
            var warnings = Set<ResourceWarning>()
            if usage.memoryBytes > thresholds.memoryBytes { warnings.insert(.memory) }
            if usage.cpuPercent >= thresholds.cpuPercent {
                let since = cpuHighSince[session.sessionId] ?? now
                nextHighSince[session.sessionId] = since
                if now.timeIntervalSince(since) >= thresholds.cpuSustain { warnings.insert(.cpu) }
            }
            guard !warnings.isEmpty else { continue }
            nextActive[session.sessionId] = warnings
            let previous = active[session.sessionId] ?? []
            for warning in [ResourceWarning.memory, .cpu] where warnings.contains(warning) && !previous.contains(warning) {
                raised.append(RaisedWarning(session: session, warning: warning))
            }
        }

        cpuHighSince = nextHighSince
        active = nextActive
        return (nextActive, raised)
    }
}

public enum SessionSort: String, CaseIterable, Identifiable, Sendable {
    case activity, memory, cpu, recent, name
    public var id: String { rawValue }
}

public enum SessionSorter {
    /// Pinned sessions come first; within each group the chosen key decides, session id breaks ties.
    public static func sorted(_ sessions: [LiveSession], by sort: SessionSort, pinned: Set<String>) -> [LiveSession] {
        sessions.sorted { a, b in
            let aPinned = pinned.contains(a.sessionId), bPinned = pinned.contains(b.sessionId)
            if aPinned != bPinned { return aPinned }
            if let ordered = compare(a, b, by: sort) { return ordered }
            return a.sessionId < b.sessionId
        }
    }

    private static func compare(_ a: LiveSession, _ b: LiveSession, by sort: SessionSort) -> Bool? {
        func descending<T: Comparable>(_ x: T, _ y: T) -> Bool? { x == y ? nil : x > y }
        let aUpdated = a.updatedAt ?? .distantPast, bUpdated = b.updatedAt ?? .distantPast
        switch sort {
        case .activity:
            if a.activity.sortRank != b.activity.sortRank { return a.activity.sortRank < b.activity.sortRank }
            return descending(aUpdated, bUpdated)
        case .memory:
            return descending(a.usage?.memoryBytes ?? 0, b.usage?.memoryBytes ?? 0) ?? descending(aUpdated, bUpdated)
        case .cpu:
            return descending(a.usage?.cpuPercent ?? 0, b.usage?.cpuPercent ?? 0) ?? descending(aUpdated, bUpdated)
        case .recent:
            return descending(aUpdated, bUpdated)
        case .name:
            let order = a.title.localizedStandardCompare(b.title)
            return order == .orderedSame ? nil : order == .orderedAscending
        }
    }
}

public struct IdleSleepPlan: Equatable, Sendable {
    public var threshold: TimeInterval
    public var sessions: [LiveSession]
    public var memoryBytes: UInt64
}

public enum IdleSleepPlanner {
    /// Idle, unpinned sessions that have been idle longer than `threshold`, longest-idle first.
    public static func plan(_ sessions: [LiveSession], idleLongerThan threshold: TimeInterval, now: Date = Date(),
                            pinned: Set<String>) -> IdleSleepPlan {
        let candidates = sessions
            .filter { $0.activity == .idle && !pinned.contains($0.sessionId) }
            .map { ($0, $0.statusSince ?? $0.updatedAt ?? .distantPast) }
            .filter { now.timeIntervalSince($0.1) > threshold }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        let memory = candidates.reduce(UInt64(0)) { $0 + ($1.usage?.memoryBytes ?? 0) }
        return IdleSleepPlan(threshold: threshold, sessions: candidates, memoryBytes: memory)
    }
}
