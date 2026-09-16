import Foundation

public enum Transcript {
    /// Claude stores transcripts under `projects/<cwd with non-alphanumerics replaced by "-">/`.
    public static func slug(for cwd: String) -> String {
        String(cwd.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        })
    }

    public static func url(projectsDir: URL, cwd: String, sessionId: String) -> URL? {
        let fm = FileManager.default
        let fileName = "\(sessionId).jsonl"
        let direct = projectsDir.appendingPathComponent(slug(for: cwd), isDirectory: true).appendingPathComponent(fileName)
        if fm.fileExists(atPath: direct.path) { return direct }

        let dirs = (try? fm.contentsOfDirectory(atPath: projectsDir.path)) ?? []
        for dir in dirs {
            let candidate = projectsDir.appendingPathComponent(dir, isDirectory: true).appendingPathComponent(fileName)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Scans the last `maxBytes` of a transcript for the most recent `ai-title` record.
    public static func lastAITitle(at url: URL, maxBytes: Int = 1_048_576) -> String? {
        info(at: url, maxBytes: maxBytes)?.aiTitle
    }

    /// Reads the newest title, prompt, model, cwd and permission mode from the transcript tail
    /// in a single reverse pass; only lines whose record type matters are JSON-decoded.
    public static func info(at url: URL, maxBytes: Int = 1_048_576) -> TranscriptInfo? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else { return nil }

        var info = TranscriptInfo(sizeBytes: size, modified: attributes[.modificationDate] as? Date)
        var promptResolved = false
        let text = String(decoding: data, as: UTF8.self)

        func decode(_ line: Substring) -> [String: Any]? {
            try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        }

        for line in text.split(separator: "\n").reversed() {
            if info.aiTitle != nil, promptResolved, info.model != nil, info.cwd != nil, info.permissionMode != nil {
                break
            }
            if info.aiTitle == nil, line.contains("\"ai-title\""), let object = decode(line),
               object["type"] as? String == "ai-title",
               let title = object["aiTitle"] as? String, !title.trimmingCharacters(in: .whitespaces).isEmpty {
                info.aiTitle = title
            } else if !promptResolved, line.contains("\"type\":\"last-prompt\""), let object = decode(line),
                      let prompt = object["lastPrompt"] as? String, let cleaned = cleanPrompt(prompt) {
                info.lastPrompt = cleaned
                promptResolved = true
            } else if line.contains("\"type\":\"user\""), let object = decode(line), object["type"] as? String == "user" {
                if info.cwd == nil { info.cwd = object["cwd"] as? String }
                if info.entrypoint == nil { info.entrypoint = object["entrypoint"] as? String }
                if !promptResolved, object["isMeta"] as? Bool != true, let prompt = promptText(object["message"]) {
                    info.lastPrompt = prompt
                    promptResolved = true
                }
            } else if info.model == nil, line.contains("\"type\":\"assistant\""), let object = decode(line),
                      let model = (object["message"] as? [String: Any])?["model"] as? String, model != "<synthetic>" {
                info.model = model
            } else if info.permissionMode == nil, line.contains("\"type\":\"permission-mode\""), let object = decode(line) {
                info.permissionMode = object["permissionMode"] as? String
            }
        }
        return info
    }

    /// First `cwd` in the transcript head whose slug matches the project folder name.
    public static func firstCwd(at url: URL, matchingSlug folder: String, maxBytes: Int = 262_144) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes) else { return nil }
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") where line.contains("\"cwd\":") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let cwd = object["cwd"] as? String else { continue }
            if slug(for: cwd) == folder { return cwd }
        }
        return nil
    }

    private static func promptText(_ message: Any?) -> String? {
        guard let message = message as? [String: Any] else { return nil }
        if let content = message["content"] as? String { return cleanPrompt(content) }
        guard let blocks = message["content"] as? [[String: Any]] else { return nil }
        for block in blocks where block["type"] as? String == "text" {
            if let text = block["text"] as? String, let cleaned = cleanPrompt(text) { return cleaned }
        }
        return nil
    }

    private static func cleanPrompt(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("<"), !text.hasPrefix("[Request interrupted"), !text.hasPrefix("Caveat:") else {
            return nil
        }
        return text
    }
}

public struct TranscriptInfo: Equatable, Sendable {
    public var aiTitle: String?
    public var lastPrompt: String?
    public var model: String?
    public var cwd: String?
    public var entrypoint: String?
    public var permissionMode: String?
    public var sizeBytes: UInt64
    public var modified: Date?

    public init(aiTitle: String? = nil, lastPrompt: String? = nil, model: String? = nil, cwd: String? = nil,
                entrypoint: String? = nil, permissionMode: String? = nil, sizeBytes: UInt64 = 0, modified: Date? = nil) {
        self.aiTitle = aiTitle
        self.lastPrompt = lastPrompt
        self.model = model
        self.cwd = cwd
        self.entrypoint = entrypoint
        self.permissionMode = permissionMode
        self.sizeBytes = sizeBytes
        self.modified = modified
    }
}

/// Memoizes transcript tails so the periodic refresh doesn't re-read large files.
public final class TranscriptCache: @unchecked Sendable {
    private struct Entry {
        var modified: Date?
        var readAt: Date
        var info: TranscriptInfo?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var urlsBySession: [String: URL] = [:]
    private let minRereadInterval: TimeInterval
    private let clock: () -> Date
    private let reader: (URL) -> TranscriptInfo?

    public init(
        minRereadInterval: TimeInterval = 15,
        clock: @escaping () -> Date = Date.init,
        reader: @escaping (URL) -> TranscriptInfo? = { Transcript.info(at: $0) }
    ) {
        self.minRereadInterval = minRereadInterval
        self.clock = clock
        self.reader = reader
    }

    public func info(for record: SessionRecord, projectsDir: URL) -> TranscriptInfo? {
        lock.lock()
        let known = urlsBySession[record.sessionId]
        lock.unlock()
        guard let url = known ?? Transcript.url(projectsDir: projectsDir, cwd: record.cwd, sessionId: record.sessionId) else {
            return nil
        }
        lock.lock()
        urlsBySession[record.sessionId] = url
        lock.unlock()
        return info(at: url)
    }

    public func info(at url: URL) -> TranscriptInfo? {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        let now = clock()
        lock.lock()
        let cached = entries[url.path]
        lock.unlock()
        if let cached {
            if cached.modified == modified { return cached.info }
            if now.timeIntervalSince(cached.readAt) < minRereadInterval { return cached.info }
        }
        let info = reader(url)
        lock.lock()
        entries[url.path] = Entry(modified: modified, readAt: now, info: info)
        lock.unlock()
        return info
    }
}
