import Foundation

public enum Liveness {
    /// Maximum allowed gap between the registry's `procStart` and the kernel's start time.
    static let startTolerance: TimeInterval = 5

    /// True when the registry entry still belongs to a running Claude Code process
    /// (guards against stale files and pids reused by unrelated processes).
    public static func isLiveClaude(_ record: SessionRecord, inspector: ProcessInspecting) -> Bool {
        guard inspector.isAlive(record.pid), let args = inspector.args(record.pid) else { return false }

        let candidates = [args.argv.first ?? "", args.executablePath].map { $0.lowercased() }
        guard candidates.contains(where: { $0.contains("claude") }) else { return false }

        guard let raw = record.procStart, let actual = inspector.startTime(record.pid) else { return true }
        let interpretations = [
            SessionRecord.parseProcStart(raw),
            SessionRecord.parseProcStart(raw, timeZone: .current),
        ].compactMap { $0 }
        guard !interpretations.isEmpty else { return true }
        return interpretations.contains { abs($0.timeIntervalSince(actual)) < startTolerance }
    }
}
