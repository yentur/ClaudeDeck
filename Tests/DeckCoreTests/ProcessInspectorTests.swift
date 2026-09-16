import Foundation
import Testing
@testable import DeckCore

/// Spawns `bash -c <script>` and returns the running Process.
func spawnBash(_ script: String, env: [String: String] = [:]) throws -> Process {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-c", script]
    p.environment = ["PATH": "/usr/bin:/bin"].merging(env) { $1 }
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try p.run()
    return p
}

/// Polls until `condition` holds or the timeout expires.
func eventually(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return condition()
}

@Suite(.serialized) struct ProcessInspectorTests {
    let inspector = SystemProcessInspector()

    @Test func readsArgvEnvStartTimeAndMemory() throws {
        let p = try spawnBash("exec -a claude /bin/sleep 60")
        defer { p.terminate(); p.waitUntilExit() }
        let pid = p.processIdentifier

        // exec replaces bash; wait until argv reflects it.
        #expect(eventually { inspector.args(pid)?.argv.first == "claude" })
        let args = try #require(inspector.args(pid))
        #expect(args.argv == ["claude", "60"])
        #expect(args.executablePath.hasSuffix("sleep"))
        #expect(inspector.isAlive(pid))
        let start = try #require(inspector.startTime(pid))
        #expect(abs(start.timeIntervalSinceNow) < 5)
        #expect((inspector.usage(pid)?.footprintBytes ?? 0) > 0)
        #expect(inspector.processTable().contains { $0.pid == pid && $0.ppid == getpid() })
    }

    // macOS hides the environment of Apple platform binaries (e.g. /bin/sleep),
    // so the live env check uses the (non-platform) test runner itself.
    @Test func readsOwnEnvironment() throws {
        let args = try #require(inspector.args(getpid()))
        let home = try #require(ProcessInfo.processInfo.environment["HOME"])
        #expect(args.env["HOME"] == home)
    }

    @Test func parsesSyntheticProcArgs() throws {
        var bytes = withUnsafeBytes(of: Int32(2)) { Array($0) }
        let payload = "/usr/bin/claude\0\0\0\0claude\0--resume\0CMUX_WORKSPACE_ID=ws-1\0A=b=c\0\0junk"
        bytes += Array(payload.utf8)
        let parsed = try #require(SystemProcessInspector.parseProcArgs(bytes))
        #expect(parsed.executablePath == "/usr/bin/claude")
        #expect(parsed.argv == ["claude", "--resume"])
        #expect(parsed.env == ["CMUX_WORKSPACE_ID": "ws-1", "A": "b=c"])
    }

    @Test func findsDescendants() throws {
        let p = try spawnBash("/bin/sleep 60 & wait")
        defer { p.terminate(); p.waitUntilExit() }
        let pid = p.processIdentifier
        #expect(eventually { !inspector.descendants(of: pid).isEmpty })
        let kids = inspector.descendants(of: pid)
        #expect(kids.contains { inspector.args($0)?.argv.first == "/bin/sleep" })
        for kid in kids { kill(kid, SIGKILL) }
    }

    @Test func deadAndZombieProcessesAreNotAlive() throws {
        let p = try spawnBash("exec /bin/sleep 60")
        let pid = p.processIdentifier
        kill(pid, SIGKILL)
        // Not yet reaped → zombie; must already count as dead.
        #expect(eventually { !inspector.isAlive(pid) })
        p.waitUntilExit()
        #expect(!inspector.isAlive(pid))
        #expect(inspector.args(99_999_999) == nil)
    }
}

struct FakeInspector: ProcessInspecting {
    var alive: Set<Int32> = []
    var starts: [Int32: Date] = [:]
    var argsByPid: [Int32: ProcArgs] = [:]
    var memory: [Int32: UInt64] = [:]
    var children: [Int32: [Int32]] = [:]
    var cpuNanos: [Int32: UInt64] = [:]
    var table: [ProcessEntry] = []
    var executables: [Int32: String] = [:]
    var ttys: [Int32: String] = [:]

    func isAlive(_ pid: Int32) -> Bool { alive.contains(pid) }
    func startTime(_ pid: Int32) -> Date? { starts[pid] }
    func args(_ pid: Int32) -> ProcArgs? { argsByPid[pid] }
    func descendants(of pid: Int32) -> [Int32] { children[pid] ?? [] }
    func usage(_ pid: Int32) -> ProcUsage? {
        guard let footprint = memory[pid] else { return nil }
        return ProcUsage(footprintBytes: footprint, cpuNanos: cpuNanos[pid] ?? 0)
    }
    func processTable() -> [ProcessEntry] { table }
    func executablePath(_ pid: Int32) -> String? { executables[pid] }
    func ttyPath(_ pid: Int32) -> String? { ttys[pid] }
}

@Suite struct LivenessTests {
    let procStart = "Sun Aug 30 07:19:16 2026"
    var startDate: Date { SessionRecord.parseProcStart(procStart)! }

    func record(procStart: String?) -> SessionRecord {
        SessionRecord(pid: 10, sessionId: "s", cwd: "/", procStart: procStart)
    }

    func inspector(argv0: String, exe: String = "/Users/x/.local/share/claude/versions/2.1.273", start: Date?) -> FakeInspector {
        var f = FakeInspector()
        f.alive = [10]
        f.argsByPid[10] = ProcArgs(executablePath: exe, argv: [argv0], env: [:])
        f.starts[10] = start
        return f
    }

    @Test func acceptsClaudeWithMatchingStart() {
        let f = inspector(argv0: "/Users/x/.local/bin/claude", start: startDate.addingTimeInterval(0.4))
        #expect(Liveness.isLiveClaude(record(procStart: procStart), inspector: f))
    }

    @Test func rejectsNonClaudeProcess() {
        let f = inspector(argv0: "node", exe: "/usr/local/bin/node", start: startDate)
        #expect(!Liveness.isLiveClaude(record(procStart: procStart), inspector: f))
    }

    @Test func rejectsReusedPidWithDifferentStart() {
        let f = inspector(argv0: "claude", start: startDate.addingTimeInterval(3600 * 5))
        #expect(!Liveness.isLiveClaude(record(procStart: procStart), inspector: f))
    }

    @Test func acceptsLocalTimeInterpretationOfProcStart() {
        let local = SessionRecord.parseProcStart(procStart, timeZone: .current)!
        let f = inspector(argv0: "claude", start: local)
        #expect(Liveness.isLiveClaude(record(procStart: procStart), inspector: f))
    }

    @Test func acceptsWhenProcStartMissing() {
        let f = inspector(argv0: "claude", start: Date())
        #expect(Liveness.isLiveClaude(record(procStart: nil), inspector: f))
    }

    @Test func rejectsDeadPid() {
        var f = inspector(argv0: "claude", start: startDate)
        f.alive = []
        #expect(!Liveness.isLiveClaude(record(procStart: procStart), inspector: f))
    }
}
