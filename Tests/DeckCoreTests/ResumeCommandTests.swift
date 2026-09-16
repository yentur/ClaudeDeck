import Foundation
import Testing
@testable import DeckCore

final class FakeRunner: CommandRunner, @unchecked Sendable {
    var calls: [(exe: String, args: [String])] = []
    var status: Int32 = 0
    var output = ""

    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        calls.append((executable, arguments))
        return CommandResult(status: status, output: output)
    }
}

@Suite struct ResumeCommandTests {
    @Test func keepsOnlyWhitelistedFlagsFromRealCmuxArgv() {
        let argv = [
            "/Users/alice/.local/bin/claude",
            "--settings", #"{"preferredNotifChannel":"notifications_disabled","hooks":{}}"#,
            "--resume", "8d7e6f5a-4b3c-4d2e-8f1a-0b9c8d7e6f5a",
            "--dangerously-skip-permissions",
        ]
        #expect(ResumeCommand.preservedFlags(from: argv) == ["--dangerously-skip-permissions"])
    }

    @Test func keepsValuedAndEqualsFormFlags() {
        let argv = ["claude", "--model=opus", "--session-id", "x", "--add-dir", "/a", "--add-dir", "/b c", "-c", "--permission-mode", "plan"]
        #expect(ResumeCommand.preservedFlags(from: argv) == ["--model=opus", "--add-dir", "/a", "--add-dir", "/b c", "--permission-mode", "plan"])
    }

    @Test func shellQuoting() {
        #expect(ResumeCommand.shellQuote("abc-123_/x.y") == "abc-123_/x.y")
        #expect(ResumeCommand.shellQuote("it's") == #"'it'\''s'"#)
        #expect(ResumeCommand.shellQuote("/b c") == "'/b c'")
        #expect(ResumeCommand.shellQuote("") == "''")
    }

    @Test func buildsResumeCommand() {
        let cmd = ResumeCommand.build(claudeBin: "claude", sessionId: "3f2c9a1e", flags: ["--dangerously-skip-permissions", "--add-dir", "/b c"])
        #expect(cmd == "claude --resume 3f2c9a1e --dangerously-skip-permissions --add-dir '/b c'")
    }
}

@Suite struct LauncherTests {
    @Test func scriptLauncherWritesExecutableScriptAndOpensIt() throws {
        let runner = FakeRunner()
        let dir = try makeTempDir().appendingPathComponent("scripts")
        let launcher = ScriptLauncher(appURL: URL(fileURLWithPath: "/Applications/cmux.app"), scriptsDir: dir, runner: runner)

        let url = try launcher.open(script: "#!/bin/bash\necho hi\n")

        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].exe == "/usr/bin/open")
        #expect(runner.calls[0].args == ["-a", "/Applications/cmux.app", url.path])
        #expect(url.pathExtension == "command")
        #expect(try String(contentsOf: url, encoding: .utf8) == "#!/bin/bash\necho hi\n")
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o700)
    }

    @Test func scriptLauncherThrowsWhenOpenFails() throws {
        let runner = FakeRunner()
        runner.status = 1
        runner.output = "boom"
        let launcher = ScriptLauncher(appURL: URL(fileURLWithPath: "/x.app"), scriptsDir: try makeTempDir(), runner: runner)
        #expect(throws: LaunchError.self) { try launcher.open(script: "") }
    }

    @Test func resumeScriptInsideCmux() {
        let script = Scripts.resume(title: "Kuzey'in işi", cwd: "/Users/alice/a b", claudeBin: "claude",
                                    sessionId: "3f2c9a1e", flags: ["--dangerously-skip-permissions"],
                                    cmuxPath: "/Applications/cmux.app/Contents/Resources/bin/cmux")
        #expect(script.hasPrefix("#!/bin/bash\nrm -f -- \"$0\"\n"))
        #expect(script.contains(#"workspace rename "$CMUX_WORKSPACE_ID" --title 'Kuzey'\''in işi'"#))
        #expect(script.contains("cd '/Users/alice/a b' || exit 1"))
        #expect(script.contains(#"[ -x "${CMUX_CLAUDE_WRAPPER_SHIM:-}" ] && claude_bin="$CMUX_CLAUDE_WRAPPER_SHIM""#))
        #expect(script.contains(#""$claude_bin" --resume 3f2c9a1e --dangerously-skip-permissions"# + "\nstatus=$?\n"))
        #expect(script.hasSuffix(#"[ -n "$CMUX_WORKSPACE_ID" ] && kill -HUP "$PPID" 2>/dev/null"# + "\nexit $status\n"))
    }

    @Test func resumeScriptWithCustomBinaryAndNoCmux() {
        let script = Scripts.resume(title: "t", cwd: "/tmp", claudeBin: "/opt/fake claude", sessionId: "id",
                                    flags: [], cmuxPath: nil)
        #expect(!script.contains("workspace rename"))
        #expect(!script.contains("CMUX_CLAUDE_WRAPPER_SHIM"))
        #expect(script.contains("claude_bin='/opt/fake claude'"))
        #expect(script.hasSuffix(#""$claude_bin" --resume id"# + "\nstatus=$?\ncase $status in 137|143) exit 0 ;; esac\nexit $status\n"))
        #expect(!script.contains("kill -HUP"))
    }

    @Test func resumeScriptActuallyRuns() throws {
        let dir = try makeTempDir()
        let log = dir.appendingPathComponent("args.log")
        let fake = dir.appendingPathComponent("fake-claude")
        try "#!/bin/bash\necho \"$PWD|$*\" > '\(log.path)'\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let script = dir.appendingPathComponent("s.command")
        try Scripts.resume(title: "t", cwd: dir.path, claudeBin: fake.path, sessionId: "abc", flags: ["--model", "opus"], cmuxPath: nil)
            .write(to: script, atomically: true, encoding: .utf8)

        let result = try ProcessRunner().run("/bin/bash", [script.path])

        #expect(result.status == 0)
        #expect(!FileManager.default.fileExists(atPath: script.path))
        let logged = try String(contentsOf: log, encoding: .utf8)
        #expect(logged.hasSuffix("|--resume abc --model opus\n"))
    }

    @Test func cmuxFocusScript() {
        let script = Scripts.cmuxFocus(workspaceId: "AB1D", cmuxPath: "/c/cmux")
        #expect(script.contains("/c/cmux workspace select AB1D"))
        #expect(script.contains(#"[ -n "$self_ws" ] && /c/cmux workspace close "$self_ws""#))
    }

    @Test func cmuxFocusHelpers() {
        #expect(CmuxFocus.selectArguments(env: [:]) == nil)
        #expect(CmuxFocus.selectArguments(env: ["CMUX_WORKSPACE_ID": "ws"]) == ["workspace", "select", "ws"])
        #expect(CmuxFocus.appBundle(containing: "/Applications/cmux.app/Contents/Resources/bin/cmux")?.path == "/Applications/cmux.app")
        #expect(CmuxFocus.appBundle(containing: "/usr/local/bin/cmux") == nil)
    }

    @Test func processRunnerDoesNotWaitForInheritedPipeWriters() throws {
        // The background sleep inherits stdout and keeps the pipe open after the shell exits.
        let started = Date()
        let result = try ProcessRunner(timeout: 10).run("/bin/sh", ["-c", "echo merhaba; /bin/sleep 4 & exit 3"])
        #expect(Date().timeIntervalSince(started) < 2.5)
        #expect(result.status == 3)
        #expect(result.output.contains("merhaba"))
    }

    @Test func processRunnerKeepsLargeOutput() throws {
        let result = try ProcessRunner(timeout: 10).run("/bin/sh", ["-c", "/usr/bin/head -c 300000 /dev/zero | /usr/bin/tr '\\\\0' a"])
        #expect(result.status == 0)
        #expect(result.output.count == 300_000)
    }

    @Test func processRunnerCapturesOutputAndStatus() throws {
        let result = try ProcessRunner().run("/bin/sh", ["-c", "echo merhaba; exit 3"])
        #expect(result.status == 3)
        #expect(result.output.contains("merhaba"))
    }
}
