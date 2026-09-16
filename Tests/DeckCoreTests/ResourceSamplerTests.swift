import Foundation
import Testing
@testable import DeckCore

@Suite struct ResourceSamplerTests {
    let mb: UInt64 = 1_048_576

    /// 10 → 11 → 12, plus 11 → 30 where 30 is itself a registered session; 20 is separate.
    func inspector() -> FakeInspector {
        var f = FakeInspector()
        f.table = [
            ProcessEntry(pid: 10, ppid: 1, startTime: 100),
            ProcessEntry(pid: 11, ppid: 10, startTime: 101),
            ProcessEntry(pid: 12, ppid: 11, startTime: 102),
            ProcessEntry(pid: 30, ppid: 11, startTime: 103),
            ProcessEntry(pid: 31, ppid: 30, startTime: 104),
            ProcessEntry(pid: 20, ppid: 1, startTime: 105),
        ]
        f.memory = [10: 300 * mb, 11: 50 * mb, 12: 10 * mb, 30: 200 * mb, 31: 5 * mb, 20: 100 * mb]
        f.cpuNanos = [10: 1_000_000_000, 11: 0, 12: 0, 30: 0, 31: 0, 20: 0]
        return f
    }

    @Test func aggregatesTreesWithoutDoubleCountingNestedSessions() {
        var now: TimeInterval = 1000
        let sampler = ResourceSampler(clock: { now })
        var f = inspector()

        let first = sampler.sample(roots: [10, 20, 30], inspector: f)
        #expect(first[10] == ResourceUsage(memoryBytes: 360 * mb, cpuPercent: 0, processCount: 3))
        #expect(first[30] == ResourceUsage(memoryBytes: 205 * mb, cpuPercent: 0, processCount: 2))
        #expect(first[20] == ResourceUsage(memoryBytes: 100 * mb, cpuPercent: 0, processCount: 1))

        now += 2
        f.cpuNanos[10] = 2_000_000_000   // +1 s CPU over 2 s → 50 %
        f.cpuNanos[12] = 500_000_000     // +0.5 s → 25 %
        f.cpuNanos[31] = 4_000_000_000   // +4 s → 200 % (multi-core)
        let second = sampler.sample(roots: [10, 20, 30], inspector: f)
        #expect(second[10]?.cpuPercent == 75)
        #expect(second[30]?.cpuPercent == 200)
        #expect(second[20]?.cpuPercent == 0)
    }

    @Test func reusedPidDoesNotProduceBogusDelta() {
        var now: TimeInterval = 0
        let sampler = ResourceSampler(clock: { now })
        var f = FakeInspector()
        f.table = [ProcessEntry(pid: 50, ppid: 1, startTime: 1)]
        f.memory = [50: mb]
        f.cpuNanos = [50: 0]
        _ = sampler.sample(roots: [50], inspector: f)

        now += 1
        f.table = [ProcessEntry(pid: 50, ppid: 1, startTime: 999)]
        f.cpuNanos = [50: 9_000_000_000]
        #expect(sampler.sample(roots: [50], inspector: f)[50]?.cpuPercent == 0)
    }

    @Test func missingUsageIsSkippedAndMemoryRoundsToMegabytes() {
        let sampler = ResourceSampler(clock: { 0 })
        var f = FakeInspector()
        f.table = [ProcessEntry(pid: 60, ppid: 1, startTime: 1), ProcessEntry(pid: 61, ppid: 60, startTime: 2)]
        f.memory = [60: 3 * mb + 12_345]
        #expect(sampler.sample(roots: [60], inspector: f)[60] == ResourceUsage(memoryBytes: 3 * mb, cpuPercent: 0, processCount: 1))
    }

    @Test(.serialized) func measuresRealBusyLoop() throws {
        let p = try spawnBash("while :; do :; done")
        defer { p.terminate(); p.waitUntilExit() }
        let sampler = ResourceSampler()
        let inspector = SystemProcessInspector()
        _ = sampler.sample(roots: [p.processIdentifier], inspector: inspector)
        Thread.sleep(forTimeInterval: 1)
        let usage = try #require(sampler.sample(roots: [p.processIdentifier], inspector: inspector)[p.processIdentifier])
        #expect(usage.cpuPercent > 50)
        #expect(usage.cpuPercent < 150)
        #expect(usage.memoryBytes > 0)
    }
}

@Suite struct UsageHistoryTests {
    @Test func keepsNewestSamplesUpToCapacity() {
        var history = UsageHistory(capacity: 3)
        for i in 0..<5 {
            history.append(UsageSample(at: Date(timeIntervalSince1970: Double(i)), memoryBytes: UInt64(i), cpuPercent: Double(i)))
        }
        #expect(history.samples.map(\.memoryBytes) == [2, 3, 4])
        #expect(history.maxCPU == 4)
        #expect(history.maxMemory == 4)
    }
}
