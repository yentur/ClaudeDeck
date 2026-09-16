import Foundation
import Testing
@testable import DeckCore

@Suite struct SnapshotBuilderTests {
    func writeRecord(_ json: String, pid: Int32, in dir: URL) throws {
        try json.write(to: dir.appendingPathComponent("\(pid).json"), atomically: true, encoding: .utf8)
    }

    @Test func buildsLiveSessionsSortedAndDeduplicated() throws {
        let root = try makeTempDir()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let projects = root.appendingPathComponent("projects", isDirectory: true)
        let transcriptDir = projects.appendingPathComponent("-Users-alice-proj", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)
        try (#"{"type":"assistant","message":{"model":"claude-opus-5"}}"# + "\n" + #"{"type":"ai-title","aiTitle":"Çalışan iş"}"#).write(
            to: transcriptDir.appendingPathComponent("busy-1.jsonl"), atomically: true, encoding: .utf8)

        try writeRecord(#"{"pid":10,"sessionId":"idle-1","cwd":"/Users/alice/proj","status":"idle","updatedAt":3000,"name":"x","nameSource":"derived"}"#, pid: 10, in: sessions)
        try writeRecord(#"{"pid":11,"sessionId":"busy-1","cwd":"/Users/alice/proj","status":"busy","updatedAt":1000,"statusUpdatedAt":900,"startedAt":500,"entrypoint":"sdk-py"}"#, pid: 11, in: sessions)
        try writeRecord(#"{"pid":12,"sessionId":"dead-1","cwd":"/","status":"busy","updatedAt":9000}"#, pid: 12, in: sessions)
        // Same session id under an older pid entry: newer updatedAt wins.
        try writeRecord(#"{"pid":13,"sessionId":"idle-1","cwd":"/Users/alice/proj","status":"idle","updatedAt":2000}"#, pid: 13, in: sessions)

        var fake = FakeInspector()
        fake.alive = [10, 11, 13]
        let claudeArgs = ProcArgs(executablePath: "/x/claude", argv: ["claude", "--dangerously-skip-permissions"],
                                  env: ["CMUX_WORKSPACE_ID": "ws", "CMUX_SURFACE_ID": "sf", "HOME": "/Users/alice",
                                        "TERM_PROGRAM": "ghostty"])
        fake.argsByPid = [10: claudeArgs, 11: claudeArgs, 13: claudeArgs]
        fake.memory = [10: UInt64(100 * 1_048_576), 11: UInt64(200 * 1_048_576 + 12_345)]
        fake.ttys = [10: "/dev/ttys007"]

        var paths = DeckPaths(env: [:], home: root)
        paths.sessionsDir = sessions
        paths.projectsDir = projects
        fake.table = [ProcessEntry(pid: 10, ppid: 1, startTime: 1), ProcessEntry(pid: 11, ppid: 1, startTime: 2),
                      ProcessEntry(pid: 13, ppid: 1, startTime: 3)]
        let builder = SnapshotBuilder(paths: paths, inspector: fake, transcripts: TranscriptCache(), sampler: ResourceSampler())

        let live = builder.build()

        #expect(live.map(\.sessionId) == ["busy-1", "idle-1"])
        let busy = live[0]
        #expect(busy.activity == .busy)
        #expect(busy.title == "Çalışan iş")
        #expect(busy.pid == 11)
        #expect(busy.entrypoint == "sdk-py")
        #expect(busy.usage == ResourceUsage(memoryBytes: UInt64(200 * 1_048_576), cpuPercent: 0, processCount: 1))
        #expect(busy.statusSince == Date(timeIntervalSince1970: 0.9))
        #expect(busy.startedAt == Date(timeIntervalSince1970: 0.5))
        #expect(busy.model == "claude-opus-5")
        #expect((busy.transcriptBytes ?? 0) > 0)
        #expect(busy.flags == ["--dangerously-skip-permissions"])
        #expect(busy.terminalEnv == ["CMUX_WORKSPACE_ID": "ws", "CMUX_SURFACE_ID": "sf", "TERM_PROGRAM": "ghostty"])
        #expect(busy.cmuxEnv == ["CMUX_WORKSPACE_ID": "ws", "CMUX_SURFACE_ID": "sf"])
        #expect(busy.host.kind == .cmux)
        #expect(busy.host.bundleID == "com.cmuxterm.app")
        #expect(busy.tty == nil)
        #expect(live[1].pid == 10)
        #expect(live[1].tty == "/dev/ttys007")
        #expect(live[1].title == "proj · idle-1")
    }

    @Test func activityFromStatus() {
        #expect(SessionActivity(status: "busy") == .busy)
        #expect(SessionActivity(status: "idle") == .idle)
        #expect(SessionActivity(status: "shell") == .shell)
        #expect(SessionActivity(status: nil) == .idle)
        #expect(SessionActivity(status: "waiting") == .other("waiting"))
    }
}

@Suite struct FormattingTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func relativeTimes() {
        #expect(Fmt.relative(now.addingTimeInterval(-59), now: now, .tr) == "şimdi")
        #expect(Fmt.relative(now.addingTimeInterval(-60), now: now, .tr) == "1 dk")
        #expect(Fmt.relative(now.addingTimeInterval(-3599), now: now, .tr) == "59 dk")
        #expect(Fmt.relative(now.addingTimeInterval(-3600), now: now, .tr) == "1 sa")
        #expect(Fmt.relative(now.addingTimeInterval(-86_400 * 4), now: now, .tr) == "4 g")
        #expect(Fmt.relative(now.addingTimeInterval(30), now: now, .tr) == "şimdi")
    }

    @Test func bytes() {
        #expect(Fmt.bytes(412 * 1_048_576) == "412 MB")
        #expect(Fmt.bytes(UInt64(1.25 * 1_073_741_824), .tr) == "1,3 GB")
        #expect(Fmt.bytes(500_000) == "<1 MB")
        #expect(Fmt.bytes(0) == "0 MB")
    }

    @Test func shortPaths() {
        #expect(Fmt.shortPath("/Users/alice", home: "/Users/alice") == "~")
        #expect(Fmt.shortPath("/Users/alice/proj", home: "/Users/alice") == "~/proj")
        #expect(Fmt.shortPath("/Users/alice/a/b/c/d", home: "/Users/alice") == "~/…/c/d")
        #expect(Fmt.shortPath("/private/tmp/x", home: "/Users/alice") == "/private/tmp/x")
        #expect(Fmt.shortPath("/Users/alicex/a", home: "/Users/alice") == "/Users/alicex/a")
    }
}
