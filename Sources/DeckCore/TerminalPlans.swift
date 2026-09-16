import Foundation

// MARK: - Resume

/// One way of getting a terminal to run a resume script.
public enum LaunchMethod: Equatable, Sendable {
    /// `open -a <app> <script>.command` (see `ScriptLauncher`).
    case openFile
    /// `/usr/bin/osascript -e <source> <arguments…>`; values reach the script only through `on run argv`.
    case appleScript(source: String, arguments: [String])
    case cli(executable: String, arguments: [String])
}

public enum ResumePlanner {
    /// The user's login shell: `$SHELL`, else the password database, else zsh.
    public static func defaultShell(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let shell = env["SHELL"], !shell.isEmpty { return shell }
        if let entry = getpwuid(getuid()), let raw = entry.pointee.pw_shell {
            let shell = String(cString: raw)
            if !shell.isEmpty { return shell }
        }
        return "/bin/zsh"
    }

    /// Launch attempts for `kind`, in order; the first one that succeeds wins.
    public static func plan(for kind: TerminalKind, scriptPath: String, cwd: String, appPath: String,
                            shell: String = "/bin/zsh") -> [LaunchMethod] {
        let script = ResumeCommand.shellQuote(scriptPath)
        switch kind {
        case .cmux, .terminalApp, .wezterm, .kitty, .warp:
            return [.openFile]
        case .ghostty:
            return [.appleScript(source: TerminalScripts.ghosttyResume, arguments: [cwd, "\(script); exit\n"]), .openFile]
        case .iterm2:
            return [.appleScript(source: TerminalScripts.iTermResume, arguments: ["\(script); exit"])]
        case .alacritty:
            return [.cli(executable: "/usr/bin/open",
                         arguments: ["-na", appPath, "--args", "--working-directory", cwd, "-e", shell, "-lic", script])]
        case .vscode, .cursor, .unknown:
            return []
        }
    }
}

/// Warp has no documented way to run a script in a new tab: open a tab in the folder and let the
/// user paste the resume command.
public enum WarpFallback {
    public static func newTabURL(cwd: String) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        guard let encoded = cwd.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "warp://action/new_tab?path=" + encoded)
    }

    public static func command(cwd: String, claudeBin: String, sessionId: String, flags: [String]) -> String {
        "cd \(ResumeCommand.shellQuote(cwd)) && " + ResumeCommand.build(claudeBin: claudeBin, sessionId: sessionId, flags: flags)
    }
}

// MARK: - AppleScript

/// AppleScript sources. Every dynamic value is passed as an argument (`item n of argv`), never
/// interpolated into the source.
public enum TerminalScripts {
    /// argv: working directory, initial input. Ghostty 1.3+ scripting API.
    public static let ghosttyResume = """
    on run argv
    \ttell application id "com.mitchellh.ghostty"
    \t\tset cfg to new surface configuration
    \t\tset initial working directory of cfg to item 1 of argv
    \t\tset initial input of cfg to item 2 of argv
    \t\tnew window with configuration cfg
    \t\tactivate
    \tend tell
    \treturn "ok"
    end run
    """

    /// argv: command line to type into a new window.
    public static let iTermResume = """
    on run argv
    \ttell application id "com.googlecode.iterm2"
    \t\tactivate
    \t\tset w to (create window with default profile)
    \t\ttell current session of w to write text (item 1 of argv)
    \tend tell
    \treturn "ok"
    end run
    """

    /// argv: tty. Returns "ok" or "notfound".
    public static let terminalAppFocus = """
    on run argv
    \ttell application id "com.apple.Terminal"
    \t\trepeat with w in windows
    \t\t\trepeat with t in tabs of w
    \t\t\t\tif tty of t is (item 1 of argv) then
    \t\t\t\t\tif miniaturized of w then set miniaturized of w to false
    \t\t\t\t\tset selected of t to true
    \t\t\t\t\tset frontmost of w to true
    \t\t\t\t\tactivate
    \t\t\t\t\treturn "ok"
    \t\t\t\tend if
    \t\t\tend repeat
    \t\tend repeat
    \tend tell
    \treturn "notfound"
    end run
    """

    /// argv: tty. Returns "ok" or "notfound".
    public static let iTermFocus = """
    on run argv
    \ttell application id "com.googlecode.iterm2"
    \t\trepeat with w in windows
    \t\t\trepeat with t in tabs of w
    \t\t\t\trepeat with s in sessions of t
    \t\t\t\t\tif tty of s is (item 1 of argv) then
    \t\t\t\t\t\tselect s
    \t\t\t\t\t\tselect t
    \t\t\t\t\t\tselect w
    \t\t\t\t\t\tactivate
    \t\t\t\t\t\treturn "ok"
    \t\t\t\t\tend if
    \t\t\t\tend repeat
    \t\t\tend repeat
    \t\tend repeat
    \tend tell
    \treturn "notfound"
    end run
    """

    /// argv: tty (may be empty), working directory (may be empty). Returns "ok" or "notfound".
    /// Ghostty 1.3 only exposes a terminal's working directory; the raw `Gtty` property is tried
    /// first for newer versions and simply errors (caught) where it doesn't exist.
    public static let ghosttyFocus = """
    on run argv
    \tset targetTTY to item 1 of argv
    \tset targetDir to item 2 of argv
    \ttell application id "com.mitchellh.ghostty"
    \t\tif targetTTY is not "" then
    \t\t\ttry
    \t\t\t\trepeat with t in terminals
    \t\t\t\t\tif («property Gtty» of t) is targetTTY then
    \t\t\t\t\t\tfocus t
    \t\t\t\t\t\tactivate
    \t\t\t\t\t\treturn "ok"
    \t\t\t\t\tend if
    \t\t\t\tend repeat
    \t\t\tend try
    \t\tend if
    \t\tif targetDir is not "" then
    \t\t\ttry
    \t\t\t\trepeat with t in terminals
    \t\t\t\t\tif (working directory of t) is targetDir then
    \t\t\t\t\t\tfocus t
    \t\t\t\t\t\tactivate
    \t\t\t\t\t\treturn "ok"
    \t\t\t\t\tend if
    \t\t\t\tend repeat
    \t\t\tend try
    \t\tend if
    \t\tactivate
    \tend tell
    \treturn "notfound"
    end run
    """

    /// Every script, for compile checks.
    public static let all: [(name: String, source: String)] = [
        ("ghosttyResume", ghosttyResume), ("iTermResume", iTermResume), ("terminalAppFocus", terminalAppFocus),
        ("iTermFocus", iTermFocus), ("ghosttyFocus", ghosttyFocus),
    ]
}

public enum AppleScriptOutcome: Equatable, Sendable {
    /// Exit status 0; the script's return value, trimmed.
    case succeeded(String)
    /// macOS Automation permission missing (error -1743).
    case notAuthorized
    case failed(String)
}

public enum AppleScript {
    public static let osascript = "/usr/bin/osascript"
    /// The first run waits for the user to answer the Automation prompt.
    public static let timeout: TimeInterval = 60
    public static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    public static func arguments(source: String, arguments: [String]) -> [String] {
        ["-e", source] + arguments
    }

    public static func outcome(_ result: CommandResult) -> AppleScriptOutcome {
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if isNotAuthorized(output) { return .notAuthorized }
        return result.status == 0 ? .succeeded(output) : .failed(output)
    }

    public static func isNotAuthorized(_ output: String) -> Bool {
        output.contains("-1743") || output.localizedCaseInsensitiveContains("Not authorized to send Apple events")
    }

    public static func run(source: String, arguments: [String], runner: CommandRunner) -> AppleScriptOutcome {
        do {
            return outcome(try runner.run(osascript, Self.arguments(source: source, arguments: arguments)))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

// MARK: - Focus

public enum FocusPlan: Equatable, Sendable {
    /// Select the cmux workspace (the app's socket / throwaway-workspace flow).
    case cmux(workspaceId: String)
    /// Select the pane in the most recently active tmux client, then focus that client's terminal.
    case tmux(TmuxInfo)
    /// Returns "ok" when it found and focused the session's tab (it activates the app itself).
    case appleScript(source: String, arguments: [String])
    /// Exit status 0 when it focused the session's pane; the app is activated afterwards.
    case cli(executable: String, arguments: [String], environment: [String: String])
    /// Just bring the host app to the front.
    case activate
}

public enum FocusPlanner {
    /// `appPath` is the host app bundle when known (needed to find kitty's / WezTerm's CLI).
    public static func plan(host: SessionHost, env: [String: String], cwd: String?, appPath: String?) -> FocusPlan {
        // tmux first: the pane's client may be attached from a different terminal (or cmux
        // workspace) than the one the tmux server, and so this environment, came from.
        if let tmux = host.tmux { return .tmux(tmux) }
        if host.kind == .cmux, let workspace = CmuxFocus.workspaceId(env: env) {
            return .cmux(workspaceId: workspace)
        }

        switch host.kind {
        case .terminalApp:
            guard let tty = host.tty else { return .activate }
            return .appleScript(source: TerminalScripts.terminalAppFocus, arguments: [tty])
        case .iterm2:
            guard let tty = host.tty else { return .activate }
            return .appleScript(source: TerminalScripts.iTermFocus, arguments: [tty])
        case .ghostty:
            return .appleScript(source: TerminalScripts.ghosttyFocus, arguments: [host.tty ?? "", cwd ?? ""])
        case .kitty:
            guard let appPath, let listenOn = nonEmpty(env["KITTY_LISTEN_ON"]), let window = nonEmpty(env["KITTY_WINDOW_ID"])
            else { return .activate }
            return .cli(executable: appPath + "/Contents/MacOS/kitten",
                        arguments: ["@", "--to", listenOn, "focus-window", "--match", "id:\(window)"], environment: [:])
        case .wezterm:
            guard let appPath, let pane = nonEmpty(env["WEZTERM_PANE"]) else { return .activate }
            var environment: [String: String] = [:]
            if let socket = nonEmpty(env["WEZTERM_UNIX_SOCKET"]) { environment["WEZTERM_UNIX_SOCKET"] = socket }
            return .cli(executable: appPath + "/Contents/MacOS/wezterm",
                        arguments: ["cli", "activate-pane", "--pane-id", pane], environment: environment)
        case .cmux, .warp, .alacritty, .vscode, .cursor, .unknown:
            return .activate
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - tmux

public struct TmuxClient: Equatable, Sendable {
    public var tty: String
    public var pid: Int32
    /// Last activity, seconds since 1970.
    public var activity: Double

    public init(tty: String, pid: Int32, activity: Double) {
        self.tty = tty
        self.pid = pid
        self.activity = activity
    }
}

public enum TmuxFocus {
    public static let binaryCandidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/opt/local/bin/tmux", "/usr/bin/tmux"]
    public static let clientFormat = "#{client_tty}\t#{client_pid}\t#{client_activity}"

    public static func locate(isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> String? {
        binaryCandidates.first(where: isExecutable)
    }

    public static func listClientsArguments(_ info: TmuxInfo) -> [String] {
        ["-S", info.socketPath, "list-clients", "-t", info.pane, "-F", clientFormat]
    }

    public static func switchClientArguments(_ info: TmuxInfo, clientTTY: String) -> [String] {
        ["-S", info.socketPath, "switch-client", "-c", clientTTY, "-t", info.pane]
    }

    public static func sessionNameArguments(_ info: TmuxInfo) -> [String] {
        ["-S", info.socketPath, "display-message", "-p", "-t", info.pane, "#{session_name}"]
    }

    /// Lines of "tty<TAB>pid<TAB>activity"; malformed lines are skipped.
    public static func parseClients(_ output: String) -> [TmuxClient] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
            guard fields.count >= 3, fields[0].hasPrefix("/"), let pid = Int32(fields[1]), let activity = Double(fields[2])
            else { return nil }
            return TmuxClient(tty: String(fields[0]), pid: pid, activity: activity)
        }
    }

    public static func mostRecentClient(_ output: String) -> TmuxClient? {
        parseClients(output).max { $0.activity < $1.activity }
    }

    /// `tmux attach -t <session>`, with `-S` only for a non-default server socket.
    public static func attachCommand(sessionName: String, socketPath: String) -> String {
        let q = ResumeCommand.shellQuote
        let socket = URL(fileURLWithPath: socketPath).lastPathComponent == "default" ? "" : "-S \(q(socketPath)) "
        return "tmux \(socket)attach -t \(q(sessionName))"
    }
}

// MARK: - Executing plans

public enum ResumeOutcome: Equatable, Sendable {
    case launched
    /// Automation was denied; `launched` tells whether a fallback still opened the session.
    case automationDenied(launched: Bool)
    case failed(String)
}

/// Runs a resume plan: writes the script once, then tries each launch method in order.
public struct ResumeExecutor: Sendable {
    public let launcher: ScriptLauncher
    public let scriptRunner: CommandRunner
    public let commandRunner: CommandRunner

    public init(launcher: ScriptLauncher, scriptRunner: CommandRunner = ProcessRunner(timeout: AppleScript.timeout),
                commandRunner: CommandRunner = ProcessRunner()) {
        self.launcher = launcher
        self.scriptRunner = scriptRunner
        self.commandRunner = commandRunner
    }

    public func run(script: String, kind: TerminalKind, cwd: String, shell: String) -> ResumeOutcome {
        let url: URL
        do {
            url = try launcher.write(script: script)
        } catch {
            return .failed(error.localizedDescription)
        }
        let plan = ResumePlanner.plan(for: kind, scriptPath: url.path, cwd: cwd, appPath: launcher.appURL.path, shell: shell)
        var denied = false
        var lastError = "\(kind.displayName) can't resume sessions"
        for method in plan {
            switch method {
            case .openFile:
                do {
                    try launcher.open(scriptAt: url)
                    return denied ? .automationDenied(launched: true) : .launched
                } catch {
                    lastError = error.localizedDescription
                }
            case .appleScript(let source, let arguments):
                switch AppleScript.run(source: source, arguments: arguments, runner: scriptRunner) {
                case .succeeded: return .launched
                case .notAuthorized: denied = true
                case .failed(let output): lastError = output
                }
            case .cli(let executable, let arguments):
                do {
                    try commandRunner.runChecked(executable, arguments)
                    return .launched
                } catch {
                    lastError = error.localizedDescription
                }
            }
        }
        try? FileManager.default.removeItem(at: url)
        return denied ? .automationDenied(launched: false) : .failed(lastError)
    }
}

public enum FocusOutcome: Equatable, Sendable {
    /// Focused the session's tab/pane (the caller still activates `FocusResult.activate` if set).
    case focused
    /// The host offers no way to target a tab; its app is just brought to the front.
    case activated
    /// Couldn't find the exact tab; the host app is brought to the front instead.
    case notFound
    case automationDenied
    /// The caller runs its cmux flow for this workspace.
    case cmux(workspaceId: String)
    /// The tmux session has no attached client; `attachCommand` reattaches it.
    case noTmuxClient(attachCommand: String)
    /// Nothing identifies the host app.
    case unknownHost
}

public struct FocusResult: Equatable, Sendable {
    public var outcome: FocusOutcome
    /// Host whose app the caller should bring to the front.
    public var activate: SessionHost?

    public init(_ outcome: FocusOutcome, activate: SessionHost? = nil) {
        self.outcome = outcome
        self.activate = activate
    }
}

/// Runs a focus plan (everything but the cmux flow and app activation, which need the app).
public struct FocusExecutor: Sendable {
    public let inspector: ProcessInspecting
    public let scriptRunner: CommandRunner
    public let commandRunner: CommandRunner
    public let tmuxPath: String?
    /// App bundle path for a bundle id (the app resolves it through LaunchServices).
    public let appPathForBundleID: @Sendable (String) -> String?

    public init(inspector: ProcessInspecting, scriptRunner: CommandRunner = ProcessRunner(timeout: AppleScript.timeout),
                commandRunner: CommandRunner = ProcessRunner(timeout: 5), tmuxPath: String? = TmuxFocus.locate(),
                appPathForBundleID: @escaping @Sendable (String) -> String? = { _ in nil }) {
        self.inspector = inspector
        self.scriptRunner = scriptRunner
        self.commandRunner = commandRunner
        self.tmuxPath = tmuxPath
        self.appPathForBundleID = appPathForBundleID
    }

    public func run(host: SessionHost, env: [String: String], cwd: String?) -> FocusResult {
        run(host: host, env: env, cwd: cwd, followTmux: true)
    }

    private func run(host: SessionHost, env: [String: String], cwd: String?, followTmux: Bool) -> FocusResult {
        var host = host
        if !followTmux { host.tmux = nil }
        let appPath = host.appPath ?? (host.bundleID ?? host.kind.bundleIDs.first).flatMap(appPathForBundleID)
        let activatable = appPath != nil || host.appPid != nil || host.bundleID != nil || !host.kind.bundleIDs.isEmpty

        switch FocusPlanner.plan(host: host, env: env, cwd: cwd, appPath: appPath) {
        case .cmux(let workspace):
            return FocusResult(.cmux(workspaceId: workspace))
        case .activate:
            return activatable ? FocusResult(.activated, activate: host) : FocusResult(.unknownHost)
        case .appleScript(let source, let arguments):
            switch AppleScript.run(source: source, arguments: arguments, runner: scriptRunner) {
            case .succeeded("ok"): return FocusResult(.focused)
            case .succeeded, .failed: return FocusResult(.notFound, activate: host)
            case .notAuthorized: return FocusResult(.automationDenied, activate: host)
            }
        case .cli(let executable, let arguments, let environment):
            let status = (try? commandRunner.run(executable, arguments, adding: environment))?.status
            return FocusResult(status == 0 ? .focused : .notFound, activate: host)
        case .tmux(let info):
            return runTmux(info, outer: host, env: env, cwd: cwd)
        }
    }

    private func runTmux(_ info: TmuxInfo, outer: SessionHost, env: [String: String], cwd: String?) -> FocusResult {
        guard let tmux = tmuxPath else {
            return run(host: outer, env: env, cwd: cwd, followTmux: false)
        }
        let listed = try? commandRunner.run(tmux, TmuxFocus.listClientsArguments(info))
        guard let listed, listed.status == 0, let client = TmuxFocus.mostRecentClient(listed.output) else {
            let name = (try? commandRunner.run(tmux, TmuxFocus.sessionNameArguments(info)))
                .flatMap { $0.status == 0 ? $0.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil }
            let target = (name?.isEmpty == false ? name : nil) ?? info.pane
            return FocusResult(.noTmuxClient(attachCommand: TmuxFocus.attachCommand(sessionName: target, socketPath: info.socketPath)))
        }
        _ = try? commandRunner.run(tmux, TmuxFocus.switchClientArguments(info, clientTTY: client.tty))

        // The client runs in a terminal of its own; focus that one.
        let clientEnv = inspector.args(client.pid)?.env ?? [:]
        var clientHost = HostResolver.resolve(
            pid: client.pid, env: clientEnv, table: inspector.processTable(), tty: client.tty,
            executablePath: { inspector.executablePath($0) ?? inspector.args($0)?.executablePath })
        clientHost.tty = client.tty
        return run(host: clientHost, env: clientEnv, cwd: nil, followTmux: false)
    }
}
