import Foundation
import Testing
@testable import DeckCore

@Suite struct RecentSessionsTests {
    func write(_ lines: [String], dir: URL, id: String, modified: TimeInterval, pad: Int = 3000) throws {
        let url = dir.appendingPathComponent("\(id).jsonl")
        let filler = #"{"type":"assistant","message":{"content":"\#(String(repeating: "x", count: pad))"}}"#
        try ([filler] + lines).joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: modified)], ofItemAtPath: url.path)
    }

    @Test func listsResumableEndedSessionsNewestFirst() throws {
        let projects = try makeTempDir()
        let a = projects.appendingPathComponent("-nowhere-alice", isDirectory: true)
        let b = projects.appendingPathComponent("-nowhere-alice-proj", isDirectory: true)
        let sub = a.appendingPathComponent("subagents", isDirectory: true)
        for d in [a, b, sub] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }

        try write([#"{"type":"user","cwd":"/nowhere/alice","entrypoint":"cli","message":{"content":"eski iş"}}"#,
                   #"{"type":"permission-mode","permissionMode":"bypassPermissions"}"#,
                   #"{"type":"ai-title","aiTitle":"gpu-price-check"}"#], dir: a, id: "old", modified: 1000)
        try write([#"{"type":"user","cwd":"/nowhere/alice/proj","entrypoint":"cli","message":{"content":"yeni iş\nikinci satır"}}"#],
                  dir: b, id: "new", modified: 3000)
        try write([#"{"type":"user","cwd":"/nowhere/alice","entrypoint":"cli","message":{"content":"canlı"}}"#], dir: a, id: "live", modified: 4000)
        try write([#"{"type":"user","cwd":"/nowhere/alice","entrypoint":"sdk-py","message":{"content":"sdk"}}"#], dir: a, id: "sdk", modified: 5000)
        try write([#"{"type":"assistant","message":{"content":"no cwd"}}"#], dir: a, id: "nocwd", modified: 6000)
        try write([#"{"type":"user","cwd":"/nowhere/alice","message":{"content":"tiny"}}"#], dir: a, id: "tiny", modified: 7000, pad: 0)
        try write([#"{"type":"user","cwd":"/nowhere/alice","message":{"content":"agent"}}"#], dir: sub, id: "agent", modified: 8000)

        let scanner = RecentSessionsScanner(projectsDir: projects, transcripts: TranscriptCache())
        let recent = scanner.scan(excluding: ["live"], limit: 10, minBytes: 2048)

        #expect(recent.map(\.sessionId) == ["new", "old"])
        #expect(recent[0].title == "yeni iş")
        #expect(recent[0].cwd == "/nowhere/alice/proj")
        #expect(recent[0].flags == [])
        #expect(recent[1].title == "Gpu price check")
        #expect(recent[1].flags == ["--dangerously-skip-permissions"])
        #expect(recent[1].modified == Date(timeIntervalSince1970: 1000))

        #expect(scanner.scan(excluding: [], limit: 1, minBytes: 2048).map(\.sessionId) == ["live"])
    }

    @Test func resumesFromProjectFolderEvenAfterClaudeChangedDirectory() throws {
        let root = try makeTempDir().resolvingSymlinksInPath()
        let project = root.appendingPathComponent("proj", isDirectory: true)
        let other = root.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let projects = root.appendingPathComponent("projects", isDirectory: true)
        let dir = projects.appendingPathComponent(Transcript.slug(for: project.path), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // The newest user entry was recorded after Claude cd'd elsewhere.
        try write([#"{"type":"user","cwd":"\#(project.path)","entrypoint":"cli","message":{"content":"başla"}}"#,
                   #"{"type":"user","cwd":"\#(other.path)","entrypoint":"cli","message":{"content":"orada devam"}}"#],
                  dir: dir, id: "moved", modified: 100, pad: 4000)

        let recent = RecentSessionsScanner(projectsDir: projects, transcripts: TranscriptCache()).scan(excluding: [])
        #expect(recent.map(\.cwd) == [project.path])
    }
}

@Suite struct LocalizedFormattingTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func englishIsTheDefault() {
        #expect(Fmt.relative(now.addingTimeInterval(-30), now: now) == "now")
        #expect(Fmt.relative(now.addingTimeInterval(-300), now: now) == "5m")
        #expect(Fmt.relative(now.addingTimeInterval(-7200), now: now) == "2h")
        #expect(Fmt.relative(now.addingTimeInterval(-86_400 * 3), now: now) == "3d")
        #expect(Fmt.bytes(UInt64(1.25 * 1_073_741_824)) == "1.3 GB")
        #expect(Fmt.bytes(24 * 1_073_741_824) == "24 GB")
        #expect(Fmt.percent(18.4) == "18%")
        #expect(Fmt.percent(0.44) == "0.4%")
        #expect(Fmt.duration(3 * 86_400 + 4 * 3600 + 60) == "3d 4h")
        #expect(Fmt.duration(2 * 3600 + 5 * 60) == "2h 5m")
        #expect(Fmt.duration(7 * 60 + 5) == "7m")
        #expect(Fmt.duration(20) == "<1m")
    }

    @Test func turkish() {
        #expect(Fmt.relative(now.addingTimeInterval(-300), now: now, .tr) == "5 dk")
        #expect(Fmt.bytes(UInt64(1.25 * 1_073_741_824), .tr) == "1,3 GB")
        #expect(Fmt.percent(18.4, .tr) == "%18")
        #expect(Fmt.percent(0.44, .tr) == "%0,4")
        #expect(Fmt.duration(3 * 86_400 + 4 * 3600, .tr) == "3g 4sa")
        #expect(Fmt.duration(20, .tr) == "<1dk")
    }
}
