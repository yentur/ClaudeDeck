import Foundation
import Testing
@testable import DeckCore

private let mb: UInt64 = 1_048_576

private func session(_ id: String, _ activity: SessionActivity, since: Double? = nil, updated: Double? = nil,
                     memory: UInt64 = 100 * mb, cpu: Double = 0, title: String? = nil) -> LiveSession {
    LiveSession(pid: 1, sessionId: id, cwd: "/", title: title ?? id, activity: activity,
                updatedAt: updated.map { Date(timeIntervalSince1970: $0) },
                usage: ResourceUsage(memoryBytes: memory, cpuPercent: cpu, processCount: 1),
                statusSince: since.map { Date(timeIntervalSince1970: $0) })
}

@Suite struct FinishDetectorTests {
    @Test func reportsWorkingToIdleAfterMinimumBusy() {
        var detector = FinishDetector(minimumBusy: 20)
        let t0 = Date(timeIntervalSince1970: 1000)

        #expect(detector.update([session("a", .busy, since: 1000), session("b", .idle, since: 900)], now: t0).isEmpty)
        #expect(detector.update([session("a", .shell, since: 1010), session("b", .idle, since: 900)], now: t0 + 10).isEmpty)
        let finished = detector.update([session("a", .idle, since: 1030), session("b", .idle, since: 900)], now: t0 + 31)
        #expect(finished.map(\.sessionId) == ["a"])
        #expect(finished.first?.worked == 30)
        // Already reported; staying idle doesn't repeat it.
        #expect(detector.update([session("a", .idle, since: 1030)], now: t0 + 40).isEmpty)
    }

    @Test func ignoresShortTurnsAndVanishedSessions() {
        var detector = FinishDetector(minimumBusy: 20)
        let t0 = Date(timeIntervalSince1970: 1000)
        _ = detector.update([session("quick", .busy, since: 1000), session("killed", .busy, since: 500)], now: t0)
        let finished = detector.update([session("quick", .idle, since: 1005)], now: t0 + 6)
        #expect(finished.isEmpty)
        // "killed" disappeared (closed), then a new session with that id shows up idle: not a finish.
        #expect(detector.update([session("killed", .idle, since: 1100)], now: t0 + 100).isEmpty)
    }

    @Test func usesRegistryStatusTimeForSessionsBusyBeforeLaunch() {
        var detector = FinishDetector(minimumBusy: 60)
        let t0 = Date(timeIntervalSince1970: 10_000)
        _ = detector.update([session("long", .busy, since: 9_000)], now: t0)
        #expect(detector.update([session("long", .idle, since: 10_003)], now: t0 + 3).map(\.sessionId) == ["long"])
    }
}

@Suite struct ResourceWarningTests {
    let limits = WarningThresholds(memoryBytes: 1024 * mb, cpuPercent: 80, cpuSustain: 60)

    @Test func memoryWarnsImmediatelyCpuOnlyWhenSustained() {
        var evaluator = ResourceWarningEvaluator(thresholds: limits)
        let t0 = Date(timeIntervalSince1970: 0)

        var result = evaluator.update([session("fat", .idle, memory: 2048 * mb), session("hot", .busy, cpu: 95)], now: t0)
        #expect(result.active["fat"] == [.memory])
        #expect(result.active["hot"] == nil)
        #expect(result.raised.map { "\($0.session.sessionId):\($0.warning)" } == ["fat:memory"])

        result = evaluator.update([session("fat", .idle, memory: 2048 * mb), session("hot", .busy, cpu: 90)], now: t0 + 61)
        #expect(result.active["hot"] == [.cpu])
        #expect(result.raised.map { "\($0.session.sessionId):\($0.warning)" } == ["hot:cpu"])

        // A dip below the limit resets the sustain timer and clears the warning.
        result = evaluator.update([session("fat", .idle, memory: 100 * mb), session("hot", .busy, cpu: 10)], now: t0 + 62)
        #expect(result.active.isEmpty)
        result = evaluator.update([session("hot", .busy, cpu: 99)], now: t0 + 90)
        #expect(result.active.isEmpty)
    }
}

@Suite struct SorterAndPlannerTests {
    let sessions = [
        session("idle-old", .idle, since: 0, updated: 100, memory: 300 * mb, cpu: 1, title: "beta"),
        session("busy", .busy, since: 900, updated: 900, memory: 200 * mb, cpu: 50, title: "Alpha"),
        session("idle-new", .idle, since: 800, updated: 800, memory: 900 * mb, cpu: 0, title: "gamma"),
        session("shell", .shell, since: 850, updated: 850, memory: 50 * mb, cpu: 90, title: "delta"),
    ]

    @Test func sortsByEachKeyWithPinsFirst() {
        func ids(_ sort: SessionSort, pinned: Set<String> = []) -> [String] {
            SessionSorter.sorted(sessions, by: sort, pinned: pinned).map(\.sessionId)
        }
        #expect(ids(.activity) == ["busy", "shell", "idle-new", "idle-old"])
        #expect(ids(.memory) == ["idle-new", "idle-old", "busy", "shell"])
        #expect(ids(.cpu) == ["shell", "busy", "idle-old", "idle-new"])
        #expect(ids(.recent) == ["busy", "shell", "idle-new", "idle-old"])
        #expect(ids(.name) == ["busy", "idle-old", "shell", "idle-new"])
        #expect(ids(.memory, pinned: ["shell"]) == ["shell", "idle-new", "idle-old", "busy"])
    }

    @Test func plansIdleSleepExcludingPinnedAndWorking() {
        let now = Date(timeIntervalSince1970: 1000)
        let plan = IdleSleepPlanner.plan(sessions, idleLongerThan: 150, now: now, pinned: [])
        #expect(plan.sessions.map(\.sessionId) == ["idle-old", "idle-new"])
        #expect(plan.memoryBytes == 1200 * mb)

        let pinnedPlan = IdleSleepPlanner.plan(sessions, idleLongerThan: 150, now: now, pinned: ["idle-new"])
        #expect(pinnedPlan.sessions.map(\.sessionId) == ["idle-old"])
        #expect(IdleSleepPlanner.plan(sessions, idleLongerThan: 5000, now: now, pinned: []).sessions.isEmpty)
    }
}
