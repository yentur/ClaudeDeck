import Foundation
import Testing
@testable import DeckCore

/// Answers commands by executable + first distinguishing argument; records every call.
final class ScriptedRunner: CommandRunner, @unchecked Sendable {
    var calls: [(exe: String, args: [String])] = []
    var respond: (String, [String]) -> CommandResult

    init(_ respond: @escaping (String, [String]) -> CommandResult = { _, _ in CommandResult(status: 0, output: "") }) {
        self.respond = respond
    }

    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        calls.append((executable, arguments))
        return respond(executable, arguments)
    }
}

@Suite struct TerminalKindTests {
    @Test func persistedRawValuesStayStable() {
        #expect(TerminalKind(rawValue: "cmux") == .cmux)
        #expect(TerminalKind(rawValue: "terminalApp") == .terminalApp)
    }

    @Test func mapsBundleIdentifiers() {
        #expect(TerminalKind(bundleID: "com.apple.Terminal") == .terminalApp)
        #expect(TerminalKind(bundleID: "COM.GOOGLECODE.ITERM2") == .iterm2)
        #expect(TerminalKind(bundleID: "dev.warp.Warp-Preview") == .warp)
        #expect(TerminalKind(bundleID: "com.microsoft.VSCodeInsiders") == .vscode)
        #expect(TerminalKind(bundleID: "com.todesktop.230313mzl4w4u92") == .cursor)
        #expect(TerminalKind(bundleID: "com.cmuxterm.app") == .cmux)
        #expect(TerminalKind(bundleID: "co.zeit.hyper") == nil)
    }

    @Test func resumableKinds() {
        #expect(TerminalKind.allCases.filter { !$0.canResume } == [.vscode, .cursor, .unknown])
        #expect(TerminalKind.iterm2.displayName == "iTerm2")
    }

    @Test func parsesTmuxEnvironment() {
        let info = TmuxInfo(env: ["TMUX": "/private/tmp/tmux-501/default,4242,0", "TMUX_PANE": "%3"])
        #expect(info == TmuxInfo(socketPath: "/private/tmp/tmux-501/default", pane: "%3"))
        #expect(TmuxInfo(env: ["TMUX": "/tmp/s,1,0"]) == nil)
        #expect(TmuxInfo(env: ["TMUX_PANE": "%1"]) == nil)
        #expect(TmuxInfo(env: ["TMUX": "/tmp/nocommas", "TMUX_PANE": "%1"])?.socketPath == "/tmp/nocommas")
    }
}

@Suite struct HostResolverTests {
    static let terminalExe = "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"

    func resolve(pid: Int32 = 100, env: [String: String] = [:], chain: [(pid: Int32, exe: String?)] = [],
                 bundles: [String: String] = [:], tty: String? = nil) -> SessionHost {
        // chain[0] is the session's parent, chain[1] its grandparent, …
        var table = [ProcessEntry]()
        var exes: [Int32: String] = [:]
        var child = pid
        for link in chain {
            table.append(ProcessEntry(pid: child, ppid: link.pid, startTime: 0))
            exes[link.pid] = link.exe
            child = link.pid
        }
        table.append(ProcessEntry(pid: child, ppid: 1, startTime: 0))
        return HostResolver.resolve(pid: pid, env: env, table: table, tty: tty,
                                    executablePath: { exes[$0] }, bundleIDForAppPath: { bundles[$0] })
    }

    @Test func cmuxEnvironment() {
        let host = resolve(env: ["CMUX_WORKSPACE_ID": "ws", "TERM_PROGRAM": "ghostty"],
                           chain: [(90, "/bin/zsh"), (80, "/usr/bin/login"), (70, "/Applications/cmux.app/Contents/MacOS/cmux")],
                           bundles: ["/Applications/cmux.app": "com.cmuxterm.app"])
        #expect(host == SessionHost(kind: .cmux, bundleID: "com.cmuxterm.app", appPath: "/Applications/cmux.app", appPid: 70))
    }

    @Test func termProgramAppleTerminal() {
        let host = resolve(env: ["TERM_PROGRAM": "Apple_Terminal"], tty: "/dev/ttys004")
        #expect(host == SessionHost(kind: .terminalApp, bundleID: "com.apple.Terminal", tty: "/dev/ttys004"))
    }

    @Test func iTermSessionId() {
        let host = resolve(env: ["ITERM_SESSION_ID": "w0t1p0:ABC"])
        #expect(host.kind == .iterm2)
        #expect(host.bundleID == "com.googlecode.iterm2")
    }

    @Test func kittyAndWezTermHints() {
        #expect(resolve(env: ["KITTY_WINDOW_ID": "3"]).kind == .kitty)
        #expect(resolve(env: ["WEZTERM_PANE": "0"]).kind == .wezterm)
        #expect(resolve(env: ["TERM_PROGRAM": "WarpTerminal"]).kind == .warp)
        #expect(resolve(env: ["__CFBundleIdentifier": "dev.warp.Warp-Preview"]).bundleID == "dev.warp.Warp-Preview")
    }

    @Test func tmuxInsideTerminalThroughParentChain() {
        let host = resolve(env: ["TMUX": "/private/tmp/tmux-501/default,555,1", "TMUX_PANE": "%7", "TERM_PROGRAM": "tmux"],
                           chain: [(90, "/bin/zsh"), (80, "/usr/bin/login"), (70, Self.terminalExe)],
                           bundles: ["/System/Applications/Utilities/Terminal.app": "com.apple.Terminal"],
                           tty: "/dev/ttys009")
        #expect(host.kind == .terminalApp)
        #expect(host.tmux == TmuxInfo(socketPath: "/private/tmp/tmux-501/default", pane: "%7"))
        #expect(host.appPath == "/System/Applications/Utilities/Terminal.app")
        #expect(host.appPid == 70)
        #expect(host.bundleID == "com.apple.Terminal")
        #expect(host.tty == "/dev/ttys009")
    }

    @Test func vsCodeNestedHelperResolvesToOutermostApp() {
        let helper = "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"
        let host = resolve(env: ["TERM_PROGRAM": "vscode"],
                           chain: [(90, "/bin/zsh"), (80, helper), (70, "/Applications/Visual Studio Code.app/Contents/MacOS/Electron")],
                           bundles: ["/Applications/Visual Studio Code.app": "com.microsoft.VSCode"])
        #expect(host == SessionHost(kind: .vscode, bundleID: "com.microsoft.VSCode", appPath: "/Applications/Visual Studio Code.app", appPid: 80))
        #expect(!host.kind.canResume)
    }

    @Test func parentChainTellsCursorFromVSCode() {
        let helper = "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin)"
        let host = resolve(env: ["TERM_PROGRAM": "vscode"], chain: [(90, "/bin/zsh"), (80, helper)],
                           bundles: ["/Applications/Cursor.app": "com.todesktop.230313mzl4w4u92"])
        #expect(host.kind == .cursor)
        #expect(host.appPath == "/Applications/Cursor.app")
    }

    @Test func leakedTmuxVariablesAreIgnoredOutsideTheServerTree() {
        // `code .` from a tmux pane: VS Code inherits TMUX, but the session doesn't descend from server 555.
        var table = [ProcessEntry(pid: 100, ppid: 90, startTime: 0), ProcessEntry(pid: 90, ppid: 80, startTime: 0),
                     ProcessEntry(pid: 80, ppid: 1, startTime: 0), ProcessEntry(pid: 555, ppid: 1, startTime: 0)]
        let exes: [Int32: String] = [90: "/bin/zsh", 80: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron"]
        let env = ["TMUX": "/private/tmp/tmux-501/default,555,0", "TMUX_PANE": "%3", "TERM_PROGRAM": "vscode"]
        var host = HostResolver.resolve(pid: 100, env: env, table: table, executablePath: { exes[$0] },
                                        bundleIDForAppPath: { _ in "com.microsoft.VSCode" })
        #expect(host.tmux == nil)
        #expect(host.kind == .vscode)

        // A real pane: the session's shell descends from the server.
        table = [ProcessEntry(pid: 100, ppid: 90, startTime: 0), ProcessEntry(pid: 90, ppid: 555, startTime: 0),
                 ProcessEntry(pid: 555, ppid: 1, startTime: 0)]
        host = HostResolver.resolve(pid: 100, env: env, table: table, executablePath: { _ in "/opt/homebrew/bin/tmux" },
                                    bundleIDForAppPath: { _ in nil })
        #expect(host.tmux?.pane == "%3")
    }

    @Test func unknownAppInChainIgnoresInheritedHints() {
        // Hyper started from an iTerm2 shell inherits ITERM_SESSION_ID; activate Hyper, not iTerm2.
        let host = resolve(env: ["ITERM_SESSION_ID": "w0t0p0:ABC", "TERM_PROGRAM": "iTerm.app"],
                           chain: [(90, "/bin/zsh"), (80, "/Applications/Hyper.app/Contents/MacOS/Hyper")],
                           bundles: ["/Applications/Hyper.app": "co.zeit.hyper"])
        #expect(host.kind == .unknown)
        #expect(host.bundleID == "co.zeit.hyper")
        #expect(host.appPath == "/Applications/Hyper.app")
    }

    @Test func parentChainBeatsInheritedCmuxEnvironment() {
        // Warp launched from a cmux shell passes CMUX_* down to its tabs (seen live).
        let host = resolve(env: ["CMUX_WORKSPACE_ID": "ws", "CMUX_SURFACE_ID": "sf"],
                           chain: [(90, "/bin/bash"), (80, "-zsh"), (70, "/Applications/Warp.app/Contents/MacOS/stable"),
                                   (60, "/Applications/Warp.app/Contents/MacOS/stable")],
                           bundles: ["/Applications/Warp.app": "dev.warp.Warp-Stable"])
        #expect(host.kind == .warp)
        #expect(host.bundleID == "dev.warp.Warp-Stable")
    }

    @Test func cmuxEnvironmentDecidesWhenChainEndsOutsideAnApp() {
        // tmux server daemonized under launchd: only the inherited environment is left.
        let host = resolve(env: ["CMUX_WORKSPACE_ID": "ws", "TMUX": "/tmp/tmux-501/default,1,0", "TMUX_PANE": "%1"],
                           chain: [(90, "/opt/homebrew/bin/tmux")], bundles: [:])
        #expect(host.kind == .cmux)
        #expect(host.tmux != nil)
    }

    @Test func parentChainBeatsInheritedBundleHint() {
        // Ghostty started from a Terminal shell inherits Terminal's __CFBundleIdentifier.
        let host = resolve(env: ["__CFBundleIdentifier": "com.apple.Terminal", "TERM_PROGRAM": "ghostty"],
                           chain: [(90, "/bin/zsh"), (80, "/Applications/Ghostty.app/Contents/MacOS/ghostty")],
                           bundles: ["/Applications/Ghostty.app": "com.mitchellh.ghostty"])
        #expect(host.kind == .ghostty)
        #expect(host.bundleID == "com.mitchellh.ghostty")
    }

    @Test func unknownWhenNothingMatches() {
        #expect(resolve(chain: [(90, "/bin/zsh"), (80, "/usr/sbin/sshd")]) == SessionHost(kind: .unknown))

        let hyper = resolve(env: ["TERM_PROGRAM": "Hyper"], chain: [(90, "/bin/zsh"), (80, "/Applications/Hyper.app/Contents/MacOS/Hyper")],
                            bundles: ["/Applications/Hyper.app": "co.zeit.hyper"])
        #expect(hyper.kind == .unknown)
        #expect(hyper.bundleID == "co.zeit.hyper")
        #expect(hyper.appName == "Hyper")
    }

    @Test func parentWalkStopsOnCyclesAndLaunchd() {
        let table = [ProcessEntry(pid: 100, ppid: 101, startTime: 0), ProcessEntry(pid: 101, ppid: 100, startTime: 0)]
        let host = HostResolver.resolve(pid: 100, env: [:], table: table, executablePath: { _ in "/bin/zsh" })
        #expect(host.kind == .unknown)

        var visited: [Int32] = []
        _ = HostResolver.resolve(pid: 100, env: [:], table: [ProcessEntry(pid: 100, ppid: 1, startTime: 0)],
                                 executablePath: { visited.append($0); return nil })
        #expect(visited.isEmpty)
    }

    @Test func outermostAppBundle() {
        #expect(HostResolver.outermostAppBundle(in: "/usr/bin/login") == nil)
        #expect(HostResolver.outermostAppBundle(in: "/Applications/Foo.app") == nil)
        #expect(HostResolver.outermostAppBundle(in: "/Applications/Foo.app/Contents/MacOS/Foo") == "/Applications/Foo.app")
        #expect(HostResolver.outermostAppBundle(in: "/Users/a/Applications/B.app/Contents/Frameworks/H.app/Contents/MacOS/H")
            == "/Users/a/Applications/B.app")
    }

    @Test func readsBundleIdentifierFromInfoPlist() throws {
        let app = try makeTempDir().appendingPathComponent("Fake Term.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "net.kovidgoyal.kitty"], format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        #expect(AppBundles.bundleID(forAppPath: app.path) == "net.kovidgoyal.kitty")
        #expect(AppBundles.bundleID(forAppPath: app.deletingLastPathComponent().appendingPathComponent("Missing.app").path) == nil)
    }
}

@Suite(.serialized) struct SystemInspectorTerminalTests {
    let inspector = SystemProcessInspector()

    @Test func executablePathOfTestRunnerAndChild() throws {
        let own = try #require(inspector.executablePath(getpid()))
        #expect(FileManager.default.fileExists(atPath: own))
        #expect(inspector.executablePath(99_999_999) == nil)

        let p = try spawnBash("exec /bin/sleep 60")
        defer { p.terminate(); p.waitUntilExit() }
        #expect(eventually { inspector.executablePath(p.processIdentifier)?.hasSuffix("/sleep") == true })
    }

    @Test func resolvesOwnHostFromLiveProcessTable() {
        let host = HostResolver.resolve(pid: getpid(), env: ProcessInfo.processInfo.environment, table: inspector.processTable(),
                                        tty: inspector.ttyPath(getpid()), executablePath: { inspector.executablePath($0) })
        // Depends on where the tests run (a terminal, an editor, CI); only check consistency.
        if let appPath = host.appPath {
            #expect(appPath.hasSuffix(".app"))
            #expect(host.appPid != nil)
        }
        #expect(host.tty == inspector.ttyPath(getpid()))
    }

    @Test func ttyFormat() throws {
        if let tty = inspector.ttyPath(getpid()) {
            #expect(tty.hasPrefix("/dev/"))
            #expect(tty != "/dev/??")
        }
        #expect(inspector.ttyPath(99_999_999) == nil)

        // `script` gives its child a pseudo-terminal as controlling tty.
        let p = try spawnBash("exec /usr/bin/script -q /dev/null /bin/sleep 60 </dev/null")
        defer { p.terminate(); p.waitUntilExit() }
        #expect(eventually { !inspector.descendants(of: p.processIdentifier).isEmpty })
        let kids = inspector.descendants(of: p.processIdentifier)
        defer { for kid in kids { kill(kid, SIGKILL) } }
        let child = try #require(kids.first)
        #expect(eventually { inspector.ttyPath(child) != nil })
        let tty = try #require(inspector.ttyPath(child))
        #expect(tty.range(of: #"^/dev/tty[a-z]*[0-9a-f]+$"#, options: .regularExpression) != nil)
        #expect(FileManager.default.fileExists(atPath: tty))
    }
}

@Suite struct ResumePlanTests {
    let script = "/Users/alice/Library/Application Support/ClaudeDeck/scripts/it's.command"
    let quoted = #"'/Users/alice/Library/Application Support/ClaudeDeck/scripts/it'\''s.command'"#

    func plan(_ kind: TerminalKind, shell: String = "/bin/zsh") -> [LaunchMethod] {
        ResumePlanner.plan(for: kind, scriptPath: script, cwd: "/Users/alice/my proj", appPath: "/Applications/X.app", shell: shell)
    }

    @Test func openFileTerminals() {
        for kind in [TerminalKind.terminalApp, .cmux, .wezterm, .kitty, .warp] {
            #expect(plan(kind) == [.openFile])
        }
    }

    @Test func ghosttyUsesAppleScriptWithFallback() {
        #expect(plan(.ghostty) == [
            .appleScript(source: TerminalScripts.ghosttyResume, arguments: ["/Users/alice/my proj", quoted + "; exit\n"]),
            .openFile,
        ])
    }

    @Test func iTermWritesTextIntoNewWindow() {
        #expect(plan(.iterm2) == [.appleScript(source: TerminalScripts.iTermResume, arguments: [quoted + "; exit"])])
    }

    @Test func alacrittyRunsScriptThroughLoginShell() {
        #expect(plan(.alacritty, shell: "/opt/homebrew/bin/fish") == [
            .cli(executable: "/usr/bin/open", arguments: [
                "-na", "/Applications/X.app", "--args", "--working-directory", "/Users/alice/my proj",
                "-e", "/opt/homebrew/bin/fish", "-lic", quoted,
            ]),
        ])
    }

    @Test func editorsCannotResume() {
        #expect(plan(.vscode).isEmpty)
        #expect(plan(.cursor).isEmpty)
        #expect(plan(.unknown).isEmpty)
    }

    @Test func scriptsNeverInterpolateValues() {
        for (_, source) in TerminalScripts.all {
            #expect(source.contains("on run argv"))
            #expect(!source.contains("\\("))
        }
    }

    @Test func defaultShell() {
        #expect(ResumePlanner.defaultShell(env: ["SHELL": "/bin/bash"]) == "/bin/bash")
        #expect(ResumePlanner.defaultShell(env: [:]).hasPrefix("/"))
    }

    @Test func warpFallback() {
        #expect(WarpFallback.newTabURL(cwd: "/Users/a b/c&d+e")?.absoluteString == "warp://action/new_tab?path=/Users/a%20b/c%26d%2Be")
        #expect(WarpFallback.command(cwd: "/Users/a b", claudeBin: "claude", sessionId: "s1", flags: ["--model", "opus"])
            == "cd '/Users/a b' && claude --resume s1 --model opus")
    }
}

@Suite struct FocusPlanTests {
    let tmux = TmuxInfo(socketPath: "/private/tmp/tmux-501/default", pane: "%2")

    @Test func cmuxSelectsWorkspace() {
        let host = SessionHost(kind: .cmux, bundleID: "com.cmuxterm.app")
        #expect(FocusPlanner.plan(host: host, env: ["CMUX_WORKSPACE_ID": "WS1"], cwd: "/", appPath: nil) == .cmux(workspaceId: "WS1"))
        #expect(FocusPlanner.plan(host: host, env: [:], cwd: "/", appPath: nil) == .activate)
    }

    @Test func tmuxComesFirst() {
        let host = SessionHost(kind: .cmux, tty: "/dev/ttys001", tmux: tmux)
        #expect(FocusPlanner.plan(host: host, env: ["CMUX_WORKSPACE_ID": "WS1"], cwd: "/", appPath: nil) == .tmux(tmux))
    }

    @Test func terminalAndITermByTTY() {
        let terminal = SessionHost(kind: .terminalApp, tty: "/dev/ttys003")
        #expect(FocusPlanner.plan(host: terminal, env: [:], cwd: nil, appPath: nil)
            == .appleScript(source: TerminalScripts.terminalAppFocus, arguments: ["/dev/ttys003"]))
        let iterm = SessionHost(kind: .iterm2, tty: "/dev/ttys004")
        #expect(FocusPlanner.plan(host: iterm, env: [:], cwd: nil, appPath: nil)
            == .appleScript(source: TerminalScripts.iTermFocus, arguments: ["/dev/ttys004"]))
        #expect(FocusPlanner.plan(host: SessionHost(kind: .terminalApp), env: [:], cwd: nil, appPath: nil) == .activate)
    }

    @Test func ghosttyByTTYOrWorkingDirectory() {
        #expect(FocusPlanner.plan(host: SessionHost(kind: .ghostty, tty: "/dev/ttys005"), env: [:], cwd: "/Users/a/p", appPath: nil)
            == .appleScript(source: TerminalScripts.ghosttyFocus, arguments: ["/dev/ttys005", "/Users/a/p"]))
        #expect(FocusPlanner.plan(host: SessionHost(kind: .ghostty), env: [:], cwd: nil, appPath: nil)
            == .appleScript(source: TerminalScripts.ghosttyFocus, arguments: ["", ""]))
    }

    @Test func kittyRemoteControl() {
        let host = SessionHost(kind: .kitty)
        let env = ["KITTY_LISTEN_ON": "unix:/tmp/kitty-77", "KITTY_WINDOW_ID": "12"]
        #expect(FocusPlanner.plan(host: host, env: env, cwd: nil, appPath: "/Applications/kitty.app")
            == .cli(executable: "/Applications/kitty.app/Contents/MacOS/kitten",
                    arguments: ["@", "--to", "unix:/tmp/kitty-77", "focus-window", "--match", "id:12"], environment: [:]))
        #expect(FocusPlanner.plan(host: host, env: ["KITTY_WINDOW_ID": "12"], cwd: nil, appPath: "/Applications/kitty.app") == .activate)
        #expect(FocusPlanner.plan(host: host, env: env, cwd: nil, appPath: nil) == .activate)
    }

    @Test func weztermActivatePane() {
        let env = ["WEZTERM_PANE": "4", "WEZTERM_UNIX_SOCKET": "/Users/a/.local/share/wezterm/gui-sock-1"]
        #expect(FocusPlanner.plan(host: SessionHost(kind: .wezterm), env: env, cwd: nil, appPath: "/Applications/WezTerm.app")
            == .cli(executable: "/Applications/WezTerm.app/Contents/MacOS/wezterm", arguments: ["cli", "activate-pane", "--pane-id", "4"],
                    environment: ["WEZTERM_UNIX_SOCKET": "/Users/a/.local/share/wezterm/gui-sock-1"]))
    }

    @Test func othersJustActivate() {
        for kind in [TerminalKind.warp, .alacritty, .vscode, .cursor, .unknown] {
            #expect(FocusPlanner.plan(host: SessionHost(kind: kind, tty: "/dev/ttys001"), env: [:], cwd: "/", appPath: "/A.app") == .activate)
        }
    }

    @Test func tmuxClientParsingPicksMostRecent() {
        let output = "/dev/ttys001\t4101\t1788000000\n/dev/ttys008\t4102\t1788000900\ngarbage line\n/dev/ttys003\t4103\t1788000500\n"
        #expect(TmuxFocus.parseClients(output).count == 3)
        #expect(TmuxFocus.mostRecentClient(output) == TmuxClient(tty: "/dev/ttys008", pid: 4102, activity: 1_788_000_900))
        #expect(TmuxFocus.mostRecentClient("") == nil)
        #expect(TmuxFocus.mostRecentClient("/dev/ttys002 55 1788000001") == TmuxClient(tty: "/dev/ttys002", pid: 55, activity: 1_788_000_001))
    }

    @Test func tmuxArguments() {
        #expect(TmuxFocus.listClientsArguments(tmux)
            == ["-S", "/private/tmp/tmux-501/default", "list-clients", "-t", "%2", "-F", "#{client_tty}\t#{client_pid}\t#{client_activity}"])
        #expect(TmuxFocus.switchClientArguments(tmux, clientTTY: "/dev/ttys008")
            == ["-S", "/private/tmp/tmux-501/default", "switch-client", "-c", "/dev/ttys008", "-t", "%2"])
        #expect(TmuxFocus.attachCommand(sessionName: "work", socketPath: tmux.socketPath) == "tmux attach -t work")
        #expect(TmuxFocus.attachCommand(sessionName: "my work", socketPath: "/tmp/custom sock")
            == "tmux -S '/tmp/custom sock' attach -t 'my work'")
        #expect(TmuxFocus.locate(isExecutable: { $0 == "/usr/local/bin/tmux" || $0 == "/usr/bin/tmux" }) == "/usr/local/bin/tmux")
        #expect(TmuxFocus.locate(isExecutable: { _ in false }) == nil)
    }

    @Test func appleScriptOutcomes() {
        #expect(AppleScript.outcome(CommandResult(status: 0, output: "ok\n")) == .succeeded("ok"))
        #expect(AppleScript.outcome(CommandResult(status: 1, output: "0:12: execution error: Not authorized to send Apple events to Terminal. (-1743)\n"))
            == .notAuthorized)
        #expect(AppleScript.outcome(CommandResult(status: 1, output: "execution error: Terminal got an error (-1728)")) == .failed("execution error: Terminal got an error (-1728)"))
        #expect(AppleScript.arguments(source: "on run argv\nend run", arguments: ["/dev/ttys001"]) == ["-e", "on run argv\nend run", "/dev/ttys001"])
    }
}

@Suite struct TerminalExecutorTests {
    let tmux = TmuxInfo(socketPath: "/private/tmp/tmux-501/default", pane: "%2")

    func executor(_ runner: ScriptedRunner, inspector: FakeInspector = FakeInspector(), tmuxPath: String? = "/opt/homebrew/bin/tmux") -> FocusExecutor {
        FocusExecutor(inspector: inspector, scriptRunner: runner, commandRunner: runner, tmuxPath: tmuxPath)
    }

    @Test func tmuxSwitchesMostRecentClientThenFocusesItsTerminalTab() {
        var inspector = FakeInspector()
        inspector.argsByPid[4102] = ProcArgs(executablePath: "/opt/homebrew/bin/tmux", argv: ["tmux", "attach"],
                                             env: ["TERM_PROGRAM": "Apple_Terminal"])
        inspector.table = [ProcessEntry(pid: 4102, ppid: 1, startTime: 0)]
        let runner = ScriptedRunner { exe, args in
            if args.contains("list-clients") {
                return CommandResult(status: 0, output: "/dev/ttys001\t4101\t10\n/dev/ttys008\t4102\t90\n")
            }
            if exe == AppleScript.osascript { return CommandResult(status: 0, output: "ok\n") }
            return CommandResult(status: 0, output: "")
        }
        let result = executor(runner, inspector: inspector).run(host: SessionHost(kind: .terminalApp, tmux: tmux), env: [:], cwd: "/")

        #expect(result == FocusResult(.focused))
        #expect(runner.calls.map(\.exe) == ["/opt/homebrew/bin/tmux", "/opt/homebrew/bin/tmux", AppleScript.osascript])
        #expect(runner.calls[1].args == TmuxFocus.switchClientArguments(tmux, clientTTY: "/dev/ttys008"))
        #expect(runner.calls[2].args == ["-e", TerminalScripts.terminalAppFocus, "/dev/ttys008"])
    }

    @Test func tmuxClientInsideCmuxHandsBackTheWorkspace() {
        var inspector = FakeInspector()
        inspector.argsByPid[7] = ProcArgs(executablePath: "tmux", argv: ["tmux"], env: ["CMUX_WORKSPACE_ID": "WS9"])
        let runner = ScriptedRunner { _, args in
            CommandResult(status: 0, output: args.contains("list-clients") ? "/dev/ttys002\t7\t1\n" : "")
        }
        let result = executor(runner, inspector: inspector).run(host: SessionHost(kind: .cmux, tmux: tmux), env: ["CMUX_WORKSPACE_ID": "OLD"], cwd: nil)
        #expect(result == FocusResult(.cmux(workspaceId: "WS9")))
    }

    @Test func tmuxWithoutClientOffersAttachCommand() {
        let runner = ScriptedRunner { _, args in
            CommandResult(status: 0, output: args.contains("display-message") ? "work\n" : "")
        }
        let result = executor(runner).run(host: SessionHost(kind: .iterm2, tmux: tmux), env: [:], cwd: nil)
        #expect(result == FocusResult(.noTmuxClient(attachCommand: "tmux attach -t work")))
    }

    @Test func appleScriptResults() {
        let host = SessionHost(kind: .terminalApp, tty: "/dev/ttys003")
        let denied = ScriptedRunner { _, _ in CommandResult(status: 1, output: "execution error: Not authorized to send Apple events to Terminal. (-1743)") }
        #expect(executor(denied).run(host: host, env: [:], cwd: nil) == FocusResult(.automationDenied, activate: host))

        let missing = ScriptedRunner { _, _ in CommandResult(status: 0, output: "notfound\n") }
        #expect(executor(missing).run(host: host, env: [:], cwd: nil) == FocusResult(.notFound, activate: host))
    }

    @Test func activateOnlyHostsAndUnknown() {
        let runner = ScriptedRunner()
        let vscode = SessionHost(kind: .vscode, bundleID: "com.microsoft.VSCode", appPath: "/Applications/Visual Studio Code.app")
        #expect(executor(runner).run(host: vscode, env: [:], cwd: nil) == FocusResult(.activated, activate: vscode))
        #expect(executor(runner).run(host: .unknown, env: [:], cwd: nil) == FocusResult(.unknownHost))
        #expect(runner.calls.isEmpty)
    }

    @Test func cliFailureStillActivates() {
        let runner = ScriptedRunner { _, _ in CommandResult(status: 1, output: "remote control is disabled") }
        let host = SessionHost(kind: .kitty, appPath: "/Applications/kitty.app")
        let env = ["KITTY_LISTEN_ON": "unix:/tmp/k", "KITTY_WINDOW_ID": "1"]
        #expect(executor(runner).run(host: host, env: env, cwd: nil) == FocusResult(.notFound, activate: host))
        #expect(runner.calls.first?.exe == "/Applications/kitty.app/Contents/MacOS/kitten")
    }

    func resume(_ kind: TerminalKind, _ runner: ScriptedRunner, dir: URL) -> ResumeOutcome {
        let launcher = ScriptLauncher(appURL: URL(fileURLWithPath: "/Applications/Term.app"), scriptsDir: dir, runner: runner)
        return ResumeExecutor(launcher: launcher, scriptRunner: runner, commandRunner: runner)
            .run(script: "#!/bin/bash\n", kind: kind, cwd: "/Users/alice/p", shell: "/bin/zsh")
    }

    func scripts(in dir: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    }

    @Test func resumeOpensScriptFile() throws {
        let dir = try makeTempDir()
        let runner = ScriptedRunner()
        #expect(resume(.terminalApp, runner, dir: dir) == .launched)
        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].exe == "/usr/bin/open")
        #expect(runner.calls[0].args.prefix(2) == ["-a", "/Applications/Term.app"])
        #expect(scripts(in: dir).count == 1)
    }

    @Test func ghosttyFallsBackToOpenFile() throws {
        let dir = try makeTempDir()
        let failing = ScriptedRunner { exe, _ in CommandResult(status: exe == AppleScript.osascript ? 1 : 0, output: "boom") }
        #expect(resume(.ghostty, failing, dir: dir) == .launched)
        #expect(failing.calls.map(\.exe) == [AppleScript.osascript, "/usr/bin/open"])
        let args = failing.calls[0].args
        #expect(args.count == 4 && args[0] == "-e" && args[2] == "/Users/alice/p" && args[3].hasSuffix(".command; exit\n"))

        let denied = ScriptedRunner { exe, _ in
            exe == AppleScript.osascript ? CommandResult(status: 1, output: "Not authorized to send Apple events to Ghostty. (-1743)")
                : CommandResult(status: 0, output: "")
        }
        #expect(resume(.ghostty, denied, dir: dir) == .automationDenied(launched: true))
    }

    @Test func failedResumeRemovesScript() throws {
        let dir = try makeTempDir()
        let denied = ScriptedRunner { _, _ in CommandResult(status: 1, output: "(-1743)") }
        #expect(resume(.iterm2, denied, dir: dir) == .automationDenied(launched: false))
        #expect(scripts(in: dir).isEmpty)

        guard case .failed = resume(.vscode, ScriptedRunner(), dir: dir) else {
            Issue.record("editors can't resume")
            return
        }
        #expect(scripts(in: dir).isEmpty)
    }
}

@Suite struct SleepRecordCompatibilityTests {
    @Test func decodesRecordsWithoutHostBundleID() throws {
        let url = try makeTempDir().appendingPathComponent("sleeping.json")
        let json = """
        [
          {"sessionId":"old-cmux","cwd":"/Users/alice/p","title":"A","flags":[],"sleptAt":"2026-08-30T07:19:16Z",
           "cmuxEnv":{"CMUX_WORKSPACE_ID":"ws"}},
          {"sessionId":"old-plain","cwd":"/Users/alice/q","title":"B","flags":["--model","opus"],"sleptAt":"2026-08-30T07:20:00Z"}
        ]
        """
        try json.write(to: url, atomically: true, encoding: .utf8)
        let store = SleepStore(url: url)
        let loaded = store.load()
        #expect(loaded.map(\.sessionId) == ["old-cmux", "old-plain"])
        #expect(loaded.allSatisfy { $0.hostBundleID == nil })
        #expect(loaded[0].resumeHostBundleID == "com.cmuxterm.app")
        #expect(loaded[1].resumeHostBundleID == nil)

        var updated = loaded[1]
        updated.hostBundleID = "com.mitchellh.ghostty"
        try store.upsert(updated)
        let reloaded = SleepStore(url: url).load().first { $0.sessionId == "old-plain" }
        #expect(reloaded?.hostBundleID == "com.mitchellh.ghostty")
        #expect(reloaded?.resumeHostBundleID == "com.mitchellh.ghostty")
    }
}

/// Compiles (never runs) every AppleScript. Compiling an `application id` block needs that app's
/// scripting dictionary, so scripts for apps that aren't installed here are skipped.
@Suite(.serialized) struct AppleScriptCompileTests {
    static func installed(_ bundleID: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let names = ["com.mitchellh.ghostty": "Ghostty.app", "com.googlecode.iterm2": "iTerm.app"]
        if bundleID == "com.apple.Terminal" { return true }
        guard let name = names[bundleID] else { return false }
        return ["/Applications/\(name)", "\(home)/Applications/\(name)"].contains { FileManager.default.fileExists(atPath: $0) }
    }

    @Test(arguments: TerminalScripts.all.map(\.name))
    func compiles(_ name: String) throws {
        let source = try #require(TerminalScripts.all.first { $0.name == name }?.source)
        let marker = try #require(source.range(of: #"application id ""#))
        let bundleID = String(source[marker.upperBound...].prefix { $0 != "\"" })
        guard Self.installed(bundleID) else { return } // e.g. iTerm2 isn't installed on this machine
        let output = try makeTempDir().appendingPathComponent("\(name).scpt")
        let result = try ProcessRunner(timeout: 60).run("/usr/bin/osacompile", ["-o", output.path, "-e", source])
        #expect(result.status == 0, "\(name): \(result.output)")
        #expect(FileManager.default.fileExists(atPath: output.path))
    }
}
