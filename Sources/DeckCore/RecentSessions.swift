import Foundation

/// An ended Claude Code session that can be resumed from its transcript.
public struct RecentSession: Identifiable, Equatable, Sendable {
    public var id: String { sessionId }
    public var sessionId: String
    public var cwd: String
    public var title: String
    public var lastPrompt: String?
    public var model: String?
    public var modified: Date
    public var sizeBytes: UInt64
    public var flags: [String]
}

public struct RecentSessionsScanner: Sendable {
    public let projectsDir: URL
    public let transcripts: TranscriptCache

    public init(projectsDir: URL, transcripts: TranscriptCache) {
        self.projectsDir = projectsDir
        self.transcripts = transcripts
    }

    /// Newest top-level transcripts (subagent transcripts live in subfolders and are skipped).
    /// Sessions without a recorded cwd, SDK-driven sessions and near-empty files are left out.
    public func scan(excluding excluded: Set<String>, limit: Int = 40, minBytes: UInt64 = 2048) -> [RecentSession] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        var candidates: [(url: URL, modified: Date)] = []

        let projectDirs = (try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        for dir in projectDirs {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
            for file in files where file.pathExtension == "jsonl" {
                let id = file.deletingPathExtension().lastPathComponent
                guard !excluded.contains(id),
                      let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                      UInt64(values.fileSize ?? 0) >= minBytes,
                      let modified = values.contentModificationDate else { continue }
                candidates.append((file, modified))
            }
        }
        candidates.sort { $0.modified > $1.modified }

        var result: [RecentSession] = []
        for candidate in candidates.prefix(limit * 3) {
            guard result.count < limit else { break }
            guard let info = transcripts.info(at: candidate.url),
                  info.entrypoint == nil || info.entrypoint == "cli",
                  let cwd = Self.projectDirectory(of: candidate.url, info: info) else { continue }
            let id = candidate.url.deletingPathExtension().lastPathComponent
            result.append(RecentSession(
                sessionId: id, cwd: cwd, title: title(info: info, cwd: cwd, id: id), lastPrompt: info.lastPrompt,
                model: info.model, modified: candidate.modified, sizeBytes: info.sizeBytes,
                flags: ResumeCommand.flags(permissionMode: info.permissionMode)
            ))
        }
        return result
    }

    /// `claude --resume` only finds a session from the directory it was started in, which is
    /// what the transcript's folder name encodes. The newest recorded cwd can differ when Claude
    /// changed directory mid-session, so look for a cwd whose slug matches the folder.
    static func projectDirectory(of transcript: URL, info: TranscriptInfo) -> String? {
        let folder = transcript.deletingLastPathComponent().lastPathComponent
        if let cwd = info.cwd, Transcript.slug(for: cwd) == folder { return cwd }
        if let cwd = Transcript.firstCwd(at: transcript, matchingSlug: folder) { return cwd }
        let naive = folder.replacingOccurrences(of: "-", with: "/")
        if Transcript.slug(for: naive) == folder, FileManager.default.fileExists(atPath: naive) { return naive }
        return nil
    }

    private func title(info: TranscriptInfo, cwd: String, id: String) -> String {
        if let ai = info.aiTitle { return TitleResolver.humanize(ai) }
        if let firstLine = info.lastPrompt?.split(separator: "\n").first {
            return firstLine.count > 70 ? String(firstLine.prefix(70)) + "…" : String(firstLine)
        }
        return "\(URL(fileURLWithPath: cwd).lastPathComponent) · \(id.prefix(8))"
    }
}
