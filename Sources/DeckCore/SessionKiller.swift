import Darwin
import Foundation

public protocol Signaler: Sendable {
    func send(_ signal: Int32, to pid: Int32)
}

public struct SystemSignaler: Signaler {
    public init() {}

    public func send(_ signal: Int32, to pid: Int32) {
        guard pid > 0 else { return }
        kill(pid, signal)
    }
}

/// Ends a session process tree: SIGTERM first, SIGKILL once the grace period
/// runs out (Claude can swallow SIGTERM), then SIGKILL any leftover descendants.
public struct SessionKiller: Sendable {
    public let inspector: ProcessInspecting
    public let signaler: Signaler
    public let grace: TimeInterval
    public let poll: TimeInterval
    public let settle: TimeInterval

    public init(inspector: ProcessInspecting, signaler: Signaler,
                grace: TimeInterval = 1.5, poll: TimeInterval = 0.1, settle: TimeInterval = 1.0) {
        self.inspector = inspector
        self.signaler = signaler
        self.grace = grace
        self.poll = poll
        self.settle = settle
    }

    /// Returns true when the root process is gone.
    public func terminate(pid: Int32) async -> Bool {
        let tree = inspector.descendants(of: pid)

        signaler.send(SIGTERM, to: pid)
        if await waitForExit(pid, within: grace) { return killLeftovers(tree) }

        signaler.send(SIGKILL, to: pid)
        _ = killLeftovers(tree)
        return await waitForExit(pid, within: settle)
    }

    @discardableResult
    private func killLeftovers(_ tree: [Int32]) -> Bool {
        for child in tree where inspector.isAlive(child) {
            signaler.send(SIGKILL, to: child)
        }
        return true
    }

    private func waitForExit(_ pid: Int32, within timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !inspector.isAlive(pid) { return true }
            try? await Task.sleep(nanoseconds: UInt64(poll * 1_000_000_000))
        }
        return !inspector.isAlive(pid)
    }
}
