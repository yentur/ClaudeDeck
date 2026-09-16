import Foundation
import Testing
@testable import DeckCore

@Suite struct SleepStoreTests {
    func sample(_ id: String, title: String = "Başlık") -> SleepingSession {
        SleepingSession(
            sessionId: id, cwd: "/Users/alice", title: title,
            flags: ["--dangerously-skip-permissions"],
            sleptAt: Date(timeIntervalSince1970: 1_788_000_000),
            cmuxEnv: ["CMUX_WORKSPACE_ID": "ws"]
        )
    }

    @Test func missingFileLoadsEmpty() throws {
        let store = SleepStore(url: try makeTempDir().appendingPathComponent("nested/sleeping.json"))
        #expect(store.load().isEmpty)
    }

    @Test func upsertPersistsAndReplaces() throws {
        let url = try makeTempDir().appendingPathComponent("nested/dir/sleeping.json")
        let store = SleepStore(url: url)
        try store.upsert(sample("a"))
        try store.upsert(sample("b"))
        try store.upsert(sample("a", title: "Güncel"))

        let reloaded = SleepStore(url: url).load()
        #expect(reloaded.map(\.sessionId) == ["b", "a"])
        #expect(reloaded.first { $0.sessionId == "a" }?.title == "Güncel")
        #expect(reloaded.first { $0.sessionId == "a" } == sample("a", title: "Güncel"))

        try store.remove(sessionId: "b")
        #expect(SleepStore(url: url).load().map(\.sessionId) == ["a"])
    }
}

@Suite(.serialized) struct SessionKillerTests {
    let inspector = SystemProcessInspector()

    @Test func killsTermIgnoringProcessAndItsChildren() async throws {
        let p = try spawnBash("trap '' TERM; /bin/sleep 60 & wait; /bin/sleep 60")
        defer { p.waitUntilExit() }
        let pid = p.processIdentifier
        #expect(eventually { !inspector.descendants(of: pid).isEmpty })
        let children = inspector.descendants(of: pid)

        let killer = SessionKiller(inspector: inspector, signaler: SystemSignaler(), grace: 1.0)
        let started = Date()
        let dead = await killer.terminate(pid: pid)

        #expect(dead)
        #expect(Date().timeIntervalSince(started) < 8)   // grace 1 s + settle; generous for slow CI runners
        #expect(!inspector.isAlive(pid))
        for child in children {
            #expect(eventually { !inspector.isAlive(child) })
        }
    }

    @Test func politeProcessDiesOnTermWithinGrace() async throws {
        let p = try spawnBash("exec /bin/sleep 60")
        defer { p.waitUntilExit() }
        let killer = SessionKiller(inspector: inspector, signaler: SystemSignaler(), grace: 1.5)
        let started = Date()
        #expect(await killer.terminate(pid: p.processIdentifier))
        #expect(Date().timeIntervalSince(started) < 1.5)
    }

    @Test func sendsTermThenKillInOrder() async {
        final class Recorder: Signaler, @unchecked Sendable {
            var sent: [(Int32, Int32)] = []
            func send(_ signal: Int32, to pid: Int32) { sent.append((signal, pid)) }
        }
        var fake = FakeInspector()
        fake.alive = [10, 11]
        fake.children = [10: [11]]
        let recorder = Recorder()
        let killer = SessionKiller(inspector: fake, signaler: recorder, grace: 0.2, poll: 0.05, settle: 0.1)

        let dead = await killer.terminate(pid: 10)

        #expect(!dead)
        #expect(recorder.sent.map(\.0) == [SIGTERM, SIGKILL, SIGKILL])
        #expect(recorder.sent.map(\.1) == [10, 10, 11])
    }
}
