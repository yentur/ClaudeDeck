import Foundation

public struct CommandResult: Equatable, Sendable {
    public var status: Int32
    public var output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }
}

public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult
    /// Runs with `environment` added on top of the runner's environment.
    func run(_ executable: String, _ arguments: [String], adding environment: [String: String]) throws -> CommandResult
}

/// Pipe output handed from the reader thread to the caller.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

extension CommandRunner {
    public func run(_ executable: String, _ arguments: [String], adding environment: [String: String]) throws -> CommandResult {
        try run(executable, arguments)
    }
}

public enum LaunchError: Error, Equatable, LocalizedError {
    case timedOut(String)
    case failed(String, status: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let exe):
            return "\(URL(fileURLWithPath: exe).lastPathComponent) timed out"
        case .failed(let exe, let status, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(URL(fileURLWithPath: exe).lastPathComponent) failed (\(status))" + (detail.isEmpty ? "" : ": \(detail)")
        }
    }
}

/// Runs a command synchronously, capturing stdout+stderr, with a hard timeout.
public struct ProcessRunner: CommandRunner {
    public var timeout: TimeInterval
    public var environment: [String: String]?

    public init(timeout: TimeInterval = 10, environment: [String: String]? = nil) {
        self.timeout = timeout
        self.environment = environment
    }

    public func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        try run(executable, arguments, adding: [:])
    }

    public func run(_ executable: String, _ arguments: [String], adding extra: [String: String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment.merging(extra) { $1 }
        } else if !extra.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(extra) { $1 }
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()

        let output = OutputBuffer()
        let readDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            output.set(pipe.fileHandleForReading.readDataToEndOfFile())
            readDone.signal()
        }

        let deadline = DispatchTime.now() + timeout
        if finished.wait(timeout: deadline) == .timedOut {
            process.terminate()
            throw LaunchError.timedOut(executable)
        }
        // The pipe drains after exit; on a busy machine that can take well over a second. Give it the
        // rest of the timeout (at least 5 s) rather than returning with the output still unread.
        _ = readDone.wait(timeout: max(deadline, .now() + 5))
        return CommandResult(status: process.terminationStatus, output: String(decoding: output.get(), as: UTF8.self))
    }
}

extension CommandRunner {
    func runChecked(_ executable: String, _ arguments: [String]) throws {
        let result = try run(executable, arguments)
        guard result.status == 0 else {
            throw LaunchError.failed(executable, status: result.status, output: result.output)
        }
    }
}

/// Writes a self-deleting `.command` script and hands it to a terminal app via `open -a`.
///
/// Going through LaunchServices matters for cmux: its control socket only trusts processes
/// started inside cmux (`socketControlMode: cmuxOnly`), so a menu-bar app can't call
/// `cmux workspace create` directly — but a script cmux runs itself is trusted. It also
/// avoids the Automation permission prompt that scripting Terminal.app would need.
public struct ScriptLauncher: Sendable {
    public let appURL: URL
    public let scriptsDir: URL
    public let runner: CommandRunner

    public init(appURL: URL, scriptsDir: URL, runner: CommandRunner = ProcessRunner()) {
        self.appURL = appURL
        self.scriptsDir = scriptsDir
        self.runner = runner
    }

    @discardableResult
    public func open(script body: String) throws -> URL {
        let url = try write(script: body)
        try open(scriptAt: url)
        return url
    }

    /// Writes an executable, uniquely named `.command` script without opening it.
    public func write(script body: String) throws -> URL {
        try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        let url = scriptsDir.appendingPathComponent("\(UUID().uuidString).command")
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    public func open(scriptAt url: URL) throws {
        try runner.runChecked("/usr/bin/open", ["-a", appURL.path, url.path])
    }

    public static let terminalAppURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
}

public enum Scripts {
    private static let header = """
    #!/bin/bash
    rm -f -- "$0"
    export CMUX_QUIET=1
    """

    /// Resumes a session. Inside cmux it also names the new workspace, prefers cmux's Claude
    /// wrapper shim (as cmux itself does) so the session keeps cmux's hooks, and closes the tab
    /// when Claude exits.
    public static func resume(title: String, cwd: String, claudeBin: String, sessionId: String,
                              flags: [String], cmuxPath: String?) -> String {
        let q = ResumeCommand.shellQuote
        var lines = [header]
        if let cmuxPath {
            lines.append(#"[ -n "$CMUX_WORKSPACE_ID" ] && \#(q(cmuxPath)) workspace rename "$CMUX_WORKSPACE_ID" --title \#(q(title)) >/dev/null 2>&1"#)
        }
        lines.append("cd \(q(cwd)) || exit 1")
        lines.append("claude_bin=\(q(claudeBin))")
        if claudeBin == "claude" {
            lines.append(#"[ -x "${CMUX_CLAUDE_WRAPPER_SHIM:-}" ] && claude_bin="$CMUX_CLAUDE_WRAPPER_SHIM""#)
        }
        let args = (["--resume", sessionId] + flags).map(q).joined(separator: " ")
        guard cmuxPath != nil else {
            // Putting a session to sleep ends Claude with SIGTERM/SIGKILL (143/137). Exit cleanly
            // then, so terminals that close windows on a clean exit don't leave dead windows behind;
            // any other failure keeps its status (and the window) so the error stays visible.
            lines.append(#""$claude_bin" \#(args)"#)
            lines.append("status=$?")
            lines.append("case $status in 137|143) exit 0 ;; esac")
            lines.append("exit $status")
            return lines.joined(separator: "\n") + "\n"
        }
        // cmux types the script into a login shell; once Claude exits (or is put to sleep),
        // hang up that shell so the tab closes like cmux's own restored Claude tabs do.
        lines.append(#""$claude_bin" \#(args)"#)
        lines.append("status=$?")
        lines.append(#"[ -n "$CMUX_WORKSPACE_ID" ] && kill -HUP "$PPID" 2>/dev/null"#)
        lines.append("exit $status")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Runs from a throwaway cmux workspace: selects the target workspace, then closes itself.
    public static func cmuxFocus(workspaceId: String, cmuxPath: String) -> String {
        let q = ResumeCommand.shellQuote
        return [
            header,
            "self_ws=\"$CMUX_WORKSPACE_ID\"",
            "\(q(cmuxPath)) workspace select \(q(workspaceId))",
            #"[ -n "$self_ws" ] && \#(q(cmuxPath)) workspace close "$self_ws""#,
        ].joined(separator: "\n") + "\n"
    }
}

/// cmux socket invocations derived from the `CMUX_*` environment of a session process.
public enum CmuxFocus {
    public static let envKeys = ["CMUX_WORKSPACE_ID", "CMUX_SURFACE_ID"]

    public static func workspaceId(env: [String: String]) -> String? {
        guard let workspace = env["CMUX_WORKSPACE_ID"], !workspace.isEmpty else { return nil }
        return workspace
    }

    public static func selectArguments(env: [String: String]) -> [String]? {
        workspaceId(env: env).map { ["workspace", "select", $0] }
    }

    public static func locate(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                              path: String? = ProcessInfo.processInfo.environment["PATH"]) -> String? {
        let bundled = "cmux.app/Contents/Resources/bin/cmux"
        var candidates = ["/Applications/\(bundled)", home.appendingPathComponent("Applications/\(bundled)").path]
        candidates += (path ?? "").split(separator: ":").map { "\($0)/cmux" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The `.app` bundle that contains the cmux CLI.
    public static func appBundle(containing cliPath: String) -> URL? {
        var url = URL(fileURLWithPath: cliPath)
        while url.path != "/" {
            if url.pathExtension == "app" { return url }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
