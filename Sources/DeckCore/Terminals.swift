import Foundation

/// Terminal (or editor) apps a Claude Code session can live in.
public enum TerminalKind: String, CaseIterable, Sendable {
    // "cmux" and "terminalApp" are persisted settings values; keep them stable.
    case cmux, terminalApp, iterm2, ghostty, warp, wezterm, kitty, alacritty, vscode, cursor, unknown

    /// Known bundle identifiers, preferred first.
    public var bundleIDs: [String] {
        switch self {
        case .cmux: return ["com.cmuxterm.app"]
        case .terminalApp: return ["com.apple.Terminal"]
        case .iterm2: return ["com.googlecode.iterm2"]
        case .ghostty: return ["com.mitchellh.ghostty"]
        case .warp: return ["dev.warp.Warp-Stable", "dev.warp.Warp-Preview"]
        case .wezterm: return ["com.github.wez.wezterm"]
        case .kitty: return ["net.kovidgoyal.kitty"]
        case .alacritty: return ["org.alacritty"] // unverified
        case .vscode: return ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
        case .cursor: return ["com.todesktop.230313mzl4w4u92"]
        case .unknown: return []
        }
    }

    public var displayName: String {
        switch self {
        case .cmux: return "cmux"
        case .terminalApp: return "Terminal"
        case .iterm2: return "iTerm2"
        case .ghostty: return "Ghostty"
        case .warp: return "Warp"
        case .wezterm: return "WezTerm"
        case .kitty: return "kitty"
        case .alacritty: return "Alacritty"
        case .vscode: return "VS Code"
        case .cursor: return "Cursor"
        case .unknown: return "Unknown"
        }
    }

    /// Whether ClaudeDeck can open a resumed session in it (editors have no scriptable "new terminal").
    public var canResume: Bool {
        switch self {
        case .vscode, .cursor, .unknown: return false
        default: return true
        }
    }

    /// Bundle identifiers are case-insensitive in LaunchServices.
    public init?(bundleID: String) {
        let wanted = bundleID.lowercased()
        guard let kind = Self.allCases.first(where: { $0.bundleIDs.contains { $0.lowercased() == wanted } }) else { return nil }
        self = kind
    }

    /// `TERM_PROGRAM` as set by the terminal. "vscode" is also what Cursor sets.
    public init?(termProgram: String) {
        switch termProgram {
        case "Apple_Terminal": self = .terminalApp
        case "iTerm.app": self = .iterm2
        case "ghostty": self = .ghostty
        case "WarpTerminal": self = .warp
        case "WezTerm": self = .wezterm
        case "vscode": self = .vscode
        default: return nil
        }
    }
}

/// A tmux pane a session runs in, from the `TMUX` / `TMUX_PANE` environment.
public struct TmuxInfo: Equatable, Hashable, Sendable {
    /// Server socket, e.g. "/private/tmp/tmux-501/default".
    public var socketPath: String
    /// Pane id, e.g. "%3".
    public var pane: String

    public init(socketPath: String, pane: String) {
        self.socketPath = socketPath
        self.pane = pane
    }

    /// `TMUX` is "<socket>,<server pid>,<session index>".
    public init?(env: [String: String]) {
        guard let tmux = env["TMUX"], let pane = env["TMUX_PANE"], !pane.isEmpty else { return nil }
        let socket = tmux.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard !socket.isEmpty else { return nil }
        self.init(socketPath: socket, pane: pane)
    }
}

/// Where a session's terminal lives: which app, its tty, and whether it's inside tmux.
public struct SessionHost: Equatable, Hashable, Sendable {
    public var kind: TerminalKind
    public var bundleID: String?
    /// Outermost `.app` bundle found among the session's ancestors.
    public var appPath: String?
    /// The ancestor process running from `appPath`.
    public var appPid: Int32?
    public var tty: String?
    public var tmux: TmuxInfo?

    public init(kind: TerminalKind, bundleID: String? = nil, appPath: String? = nil, appPid: Int32? = nil,
                tty: String? = nil, tmux: TmuxInfo? = nil) {
        self.kind = kind
        self.bundleID = bundleID
        self.appPath = appPath
        self.appPid = appPid
        self.tty = tty
        self.tmux = tmux
    }

    public static let unknown = SessionHost(kind: .unknown)

    /// App name for hosts that aren't a known terminal ("Hyper", "Zed", …).
    public var appName: String? {
        appPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
    }
}

/// pid → parent pid over a process table snapshot.
public struct ProcessParents: Sendable {
    private let parentByPid: [Int32: Int32]

    public init(_ table: [ProcessEntry]) {
        var parents: [Int32: Int32] = [:]
        parents.reserveCapacity(table.count)
        for entry in table where entry.pid != entry.ppid {
            parents[entry.pid] = entry.ppid
        }
        parentByPid = parents
    }

    public func parent(of pid: Int32) -> Int32? { parentByPid[pid] }

    public func contains(_ pid: Int32) -> Bool { parentByPid[pid] != nil }

    /// Whether `ancestor` appears in `pid`'s parent chain (bounded walk).
    public func isAncestor(_ ancestor: Int32, of pid: Int32, maxHops: Int = 64) -> Bool {
        var current = parent(of: pid)
        var hops = 0
        while let candidate = current, candidate > 0, hops < maxHops {
            if candidate == ancestor { return true }
            current = parent(of: candidate)
            hops += 1
        }
        return false
    }
}

/// Figures out which terminal app a session runs in.
public enum HostResolver {
    /// Environment keys worth keeping from a session process.
    public static let envKeys: [String] = CmuxFocus.envKeys + [
        "TERM_PROGRAM", "__CFBundleIdentifier", "TMUX", "TMUX_PANE", "ITERM_SESSION_ID",
        "KITTY_WINDOW_ID", "KITTY_LISTEN_ON", "WEZTERM_PANE", "WEZTERM_UNIX_SOCKET",
    ]

    static let maxHops = 32

    public static func resolve(pid: Int32, env: [String: String], table: [ProcessEntry], tty: String? = nil,
                               executablePath: (Int32) -> String?,
                               bundleIDForAppPath: (String) -> String? = AppBundles.bundleID(forAppPath:)) -> SessionHost {
        resolve(pid: pid, env: env, parents: ProcessParents(table), tty: tty,
                executablePath: executablePath, bundleIDForAppPath: bundleIDForAppPath)
    }

    /// The parent-process chain wins when it reaches a known terminal: the process tree is ground
    /// truth, the only way to tell Cursor from VS Code (both set `TERM_PROGRAM=vscode`), and immune to
    /// variables such as `CMUX_WORKSPACE_ID` inherited by apps launched from a cmux shell. Otherwise the
    /// hints decide (cmux environment first). tmux is always recorded; inside tmux the chain usually
    /// ends at the daemonized server, so the hints are all there is.
    public static func resolve(pid: Int32, env: [String: String], parents: ProcessParents, tty: String? = nil,
                               executablePath: (Int32) -> String?,
                               bundleIDForAppPath: (String) -> String? = AppBundles.bundleID(forAppPath:)) -> SessionHost {
        var tmux = TmuxInfo(env: env)
        // `TMUX` also leaks into apps started from a tmux pane (e.g. `code .`). A real pane's shell
        // descends from the tmux server, whose pid is the second field of `TMUX`.
        if tmux != nil, let server = tmuxServerPid(env: env), parents.contains(server),
           !parents.isAncestor(server, of: pid) {
            tmux = nil
        }
        let hint: TerminalKind? = CmuxFocus.workspaceId(env: env) != nil ? .cmux : envHint(env)

        let chain = hostApp(of: pid, parents: parents, executablePath: executablePath)
        let chainBundleID = chain.flatMap { bundleIDForAppPath($0.appPath) }
        let chainKind = chainBundleID.flatMap(TerminalKind.init(bundleID:))

        // The process tree is ground truth whenever it reaches a known terminal: environment
        // variables (including CMUX_*) leak into apps launched from a shell inside another terminal.
        // If the chain reaches an app that isn't a known terminal, inherited hints are unreliable too.
        let kind: TerminalKind = chainKind ?? (chainBundleID == nil ? hint : nil) ?? .unknown

        var host = SessionHost(kind: kind, tty: tty, tmux: tmux)
        if let chain, chainKind == kind || kind == .unknown {
            host.appPath = chain.appPath
            host.appPid = chain.pid
            host.bundleID = chainBundleID
        } else if let envBundle = env["__CFBundleIdentifier"], !envBundle.isEmpty,
                  kind == .unknown || TerminalKind(bundleID: envBundle) == kind {
            host.bundleID = envBundle
        } else {
            host.bundleID = kind.bundleIDs.first
        }
        return host
    }

    static func tmuxServerPid(env: [String: String]) -> Int32? {
        guard let tmux = env["TMUX"] else { return nil }
        let fields = tmux.split(separator: ",", omittingEmptySubsequences: false)
        return fields.count >= 2 ? Int32(fields[1]) : nil
    }

    static func envHint(_ env: [String: String]) -> TerminalKind? {
        if let id = env["__CFBundleIdentifier"], let kind = TerminalKind(bundleID: id) { return kind }
        if let program = env["TERM_PROGRAM"], let kind = TerminalKind(termProgram: program) { return kind }
        if env["ITERM_SESSION_ID"]?.isEmpty == false { return .iterm2 }
        if env["KITTY_WINDOW_ID"]?.isEmpty == false { return .kitty }
        if env["WEZTERM_PANE"]?.isEmpty == false { return .wezterm }
        return nil
    }

    /// First ancestor (not the session process itself) running from inside an `.app` bundle.
    static func hostApp(of pid: Int32, parents: ProcessParents,
                        executablePath: (Int32) -> String?) -> (pid: Int32, appPath: String)? {
        var current = parents.parent(of: pid)
        var hops = 0
        while let ancestor = current, ancestor > 1, hops < maxHops {
            if let path = executablePath(ancestor), let app = outermostAppBundle(in: path) {
                return (ancestor, app)
            }
            current = parents.parent(of: ancestor)
            hops += 1
        }
        return nil
    }

    /// "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"
    /// → "/Applications/Visual Studio Code.app" (helper apps are nested inside the main app).
    public static func outermostAppBundle(in path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        // The bundle must contain something (the executable), so never match the last component.
        for index in components.indices.dropLast() where components[index].lowercased().hasSuffix(".app") {
            let prefix = components[...index].joined(separator: "/")
            return prefix.isEmpty ? nil : prefix
        }
        return nil
    }
}

/// Reads `CFBundleIdentifier` from app bundles, cached (a handful of apps, looked up every refresh).
public enum AppBundles {
    private static let cache = BundleIDCache()

    public static func bundleID(forAppPath path: String) -> String? {
        cache.value(for: path) {
            let plist = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
            guard let data = FileManager.default.contents(atPath: plist.path),
                  let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { return nil }
            return info["CFBundleIdentifier"] as? String
        }
    }
}

private final class BundleIDCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String?] = [:]

    func value(for key: String, compute: () -> String?) -> String? {
        lock.lock()
        if let cached = values[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let value = compute()
        lock.lock()
        if values.count > 256 { values.removeAll() }
        values[key] = .some(value)
        lock.unlock()
        return value
    }
}
