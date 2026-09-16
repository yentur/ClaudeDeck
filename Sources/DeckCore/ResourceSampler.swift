import Foundation

/// Parent → children index over a process table snapshot.
struct ProcessTree {
    let childrenByParent: [Int32: [Int32]]
    let startByPid: [Int32: Double]

    init(_ table: [ProcessEntry]) {
        var children: [Int32: [Int32]] = [:]
        var starts: [Int32: Double] = [:]
        for entry in table where entry.pid != entry.ppid {
            children[entry.ppid, default: []].append(entry.pid)
            starts[entry.pid] = entry.startTime
        }
        childrenByParent = children
        startByPid = starts
    }

    /// Breadth-first descendants (shallow first). Subtrees rooted at `stopAt` pids are skipped.
    func descendants(of root: Int32, stopAt: Set<Int32> = []) -> [Int32] {
        var ordered: [Int32] = []
        var frontier = childrenByParent[root] ?? []
        while !frontier.isEmpty {
            let kept = frontier.filter { !stopAt.contains($0) }
            ordered.append(contentsOf: kept)
            frontier = kept.flatMap { childrenByParent[$0] ?? [] }
        }
        return ordered
    }
}

public struct ResourceUsage: Equatable, Sendable {
    /// Footprint of the session process and its descendants, whole megabytes.
    public var memoryBytes: UInt64
    /// Activity Monitor convention: 100 = one full core.
    public var cpuPercent: Double
    public var processCount: Int

    public init(memoryBytes: UInt64, cpuPercent: Double, processCount: Int) {
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
        self.processCount = processCount
    }
}

/// Samples memory and CPU for session process trees. CPU is the delta of consumed CPU time
/// between consecutive samples, so the first sample of a process reports 0 %.
public final class ResourceSampler: @unchecked Sendable {
    private struct Key: Hashable {
        let pid: Int32
        let start: Double
    }

    private let lock = NSLock()
    private let clock: () -> TimeInterval
    private var previous: [Key: UInt64] = [:]
    private var previousAt: TimeInterval?

    public init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }

    /// `table` lets a caller that already fetched the process table share it.
    public func sample(roots: [Int32], inspector: ProcessInspecting, table: [ProcessEntry]? = nil) -> [Int32: ResourceUsage] {
        let tree = ProcessTree(table ?? inspector.processTable())
        let rootSet = Set(roots)
        let now = clock()

        lock.lock()
        defer { lock.unlock() }
        let elapsed = previousAt.map { now - $0 } ?? 0
        var current: [Key: UInt64] = [:]
        var result: [Int32: ResourceUsage] = [:]

        for root in rootSet {
            // A session nested inside another session's tree is counted only under itself.
            let pids = [root] + tree.descendants(of: root, stopAt: rootSet.subtracting([root]))
            var memory: UInt64 = 0
            var cpuNanos: Double = 0
            var count = 0
            for pid in pids {
                guard let usage = inspector.usage(pid) else { continue }
                count += 1
                memory += usage.footprintBytes
                let key = Key(pid: pid, start: tree.startByPid[pid] ?? 0)
                current[key] = usage.cpuNanos
                if elapsed > 0, let before = previous[key], usage.cpuNanos >= before {
                    cpuNanos += Double(usage.cpuNanos - before)
                }
            }
            let percent = elapsed > 0 ? (cpuNanos / (elapsed * 1_000_000_000) * 100 * 10).rounded() / 10 : 0
            result[root] = ResourceUsage(memoryBytes: memory / 1_048_576 * 1_048_576, cpuPercent: percent, processCount: count)
        }

        previous = current
        previousAt = now
        return result
    }
}

public struct UsageSample: Equatable, Sendable {
    public var at: Date
    public var memoryBytes: UInt64
    public var cpuPercent: Double

    public init(at: Date, memoryBytes: UInt64, cpuPercent: Double) {
        self.at = at
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
    }
}

/// Fixed-size history of total usage, oldest first (for sparklines).
public struct UsageHistory: Equatable, Sendable {
    public let capacity: Int
    public private(set) var samples: [UsageSample] = []

    public init(capacity: Int = 200) {
        self.capacity = capacity
    }

    public mutating func append(_ sample: UsageSample) {
        samples.append(sample)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    public var maxCPU: Double { samples.map(\.cpuPercent).max() ?? 0 }
    public var maxMemory: UInt64 { samples.map(\.memoryBytes).max() ?? 0 }
}
