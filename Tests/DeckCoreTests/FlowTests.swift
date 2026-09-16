import Foundation
import Testing
@testable import DeckCore

/// Sleep → wake without the UI: record, kill the process, then run the generated resume script.
@Suite(.serialized) struct FlowTests {
    @Test func sleepThenWakeRoundTrip() async throws {
        let dir = try makeTempDir()
        let inspector = SystemProcessInspector()
        let session = try spawnBash("exec -a claude /bin/sleep 60")
        defer { session.waitUntilExit() }
        let pid = session.processIdentifier
        #expect(eventually { inspector.args(pid)?.argv.first == "claude" })

        // Sleep: persist what's needed to resume, then end the process.
        let store = SleepStore(url: dir.appendingPathComponent("sleeping.json"))
        let flags = ResumeCommand.preservedFlags(from: ["claude", "--dangerously-skip-permissions", "--settings", "{}"])
        try store.upsert(SleepingSession(sessionId: "flow-1", cwd: dir.path, title: "Akış testi",
                                         flags: flags, sleptAt: Date(), cmuxEnv: nil))
        let killer = SessionKiller(inspector: inspector, signaler: SystemSignaler(), grace: 1)
        #expect(await killer.terminate(pid: pid))

        // Wake: the resume script must reach the claude binary with the saved id and flags.
        let entry = try #require(store.load().first)
        let log = dir.appendingPathComponent("resume.log")
        let fakeClaude = dir.appendingPathComponent("claude")
        try "#!/bin/bash\necho \"$PWD $*\" > '\(log.path)'\n".write(to: fakeClaude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeClaude.path)
        let script = Scripts.resume(title: entry.title, cwd: entry.cwd, claudeBin: fakeClaude.path,
                                    sessionId: entry.sessionId, flags: entry.flags, cmuxPath: nil)
        let scriptURL = dir.appendingPathComponent("wake.command")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        #expect(try ProcessRunner().run("/bin/bash", [scriptURL.path]).status == 0)
        let logged = try String(contentsOf: log, encoding: .utf8)
        #expect(logged.hasSuffix(" --resume flow-1 --dangerously-skip-permissions\n"))
        #expect(logged.hasPrefix(dir.resolvingSymlinksInPath().path) || logged.hasPrefix(dir.path))

        try store.remove(sessionId: "flow-1")
        #expect(store.load().isEmpty)
    }
}
