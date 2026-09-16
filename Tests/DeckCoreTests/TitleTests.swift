import Foundation
import Testing
@testable import DeckCore

@Suite struct TranscriptTitleTests {
    func writeLines(_ lines: [String], to url: URL) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func returnsLastAITitle() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("s.jsonl")
        try writeLines([
            #"{"type":"user","message":{"content":"merhaba"}}"#,
            #"{"type":"ai-title","aiTitle":"Eski başlık","sessionId":"s"}"#,
            #"{"type":"assistant","message":{}}"#,
            #"{"type":"ai-title","aiTitle":"Yeni başlık","sessionId":"s"}"#,
            #"{"type":"last-prompt","lastPrompt":"x"}"#,
        ], to: file)
        #expect(Transcript.lastAITitle(at: file) == "Yeni başlık")
    }

    @Test func findsTitleNearEndOfLargeFile() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("big.jsonl")
        let filler = String(repeating: #"{"type":"assistant","message":{"text":"lorem ipsum dolor sit amet"}}"# + "\n", count: 30_000)
        try (filler + #"{"type":"ai-title","aiTitle":"Sondaki başlık","sessionId":"s"}"# + "\n" + filler.prefix(4000))
            .write(to: file, atomically: true, encoding: .utf8)
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as! Int
        #expect(size > 2_000_000)
        #expect(Transcript.lastAITitle(at: file, maxBytes: 1_048_576) == "Sondaki başlık")
    }

    @Test func returnsNilWithoutTitle() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("none.jsonl")
        try writeLines([#"{"type":"user"}"#], to: file)
        #expect(Transcript.lastAITitle(at: file) == nil)
        #expect(Transcript.lastAITitle(at: dir.appendingPathComponent("missing.jsonl")) == nil)
    }

    @Test func slugReplacesNonAlphanumerics() {
        #expect(Transcript.slug(for: "/Users/alice/a.b_c") == "-Users-alice-a-b-c")
        #expect(Transcript.slug(for: "/Users/alice") == "-Users-alice")
    }

    @Test func locatesTranscriptBySlugOrScan() throws {
        let projects = try makeTempDir()
        let slugDir = projects.appendingPathComponent("-Users-alice", isDirectory: true)
        let otherDir = projects.appendingPathComponent("weird", isDirectory: true)
        try FileManager.default.createDirectory(at: slugDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        try "".write(to: slugDir.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        try "".write(to: otherDir.appendingPathComponent("b.jsonl"), atomically: true, encoding: .utf8)

        #expect(Transcript.url(projectsDir: projects, cwd: "/Users/alice", sessionId: "a")?.lastPathComponent == "a.jsonl")
        #expect(Transcript.url(projectsDir: projects, cwd: "/Users/alice", sessionId: "b")?.deletingLastPathComponent().lastPathComponent == "weird")
        #expect(Transcript.url(projectsDir: projects, cwd: "/Users/alice", sessionId: "zzz") == nil)
    }
}

@Suite struct TitleResolverTests {
    func record(name: String?, source: String?, cwd: String = "/Users/alice/proje") -> SessionRecord {
        SessionRecord(pid: 1, sessionId: "3f2c9a1e-7b4d-4e8f", cwd: cwd, name: name, nameSource: source)
    }

    @Test func userRenamedNameWins() {
        #expect(TitleResolver.resolve(record(name: "billing-migration", source: nil), aiTitle: "AI") == "Billing migration")
        #expect(TitleResolver.resolve(record(name: "Benim adım", source: "user"), aiTitle: "AI") == "Benim adım")
    }

    @Test func aiTitleBeatsDerivedAndAutoNames() {
        #expect(TitleResolver.resolve(record(name: "alice-fd", source: "derived"), aiTitle: "Fix flaky CI") == "Fix flaky CI")
        #expect(TitleResolver.resolve(record(name: "godot-zombie", source: "auto"), aiTitle: "Zombi oyunu") == "Zombi oyunu")
    }

    @Test func autoNameUsedWithoutAITitle() {
        #expect(TitleResolver.resolve(record(name: "godot-zombie-runner", source: "auto"), aiTitle: nil) == "Godot zombie runner")
    }

    @Test func humanizesKebabCaseOnly() {
        #expect(TitleResolver.resolve(record(name: "x", source: "derived"), aiTitle: "claude-deck-app-plan") == "Claude deck app plan")
        #expect(TitleResolver.resolve(record(name: "billing-migration-v2", source: nil), aiTitle: nil) == "Billing migration v2")
        #expect(TitleResolver.humanize("EC2 SSH key-pair denied") == "EC2 SSH key-pair denied")
        #expect(TitleResolver.humanize("tek") == "tek")
    }

    @Test func fallsBackToFolderAndShortId() {
        #expect(TitleResolver.resolve(record(name: "alice-fd", source: "derived"), aiTitle: nil) == "proje · 3f2c9a1e")
        #expect(TitleResolver.resolve(record(name: "", source: nil), aiTitle: "  ") == "proje · 3f2c9a1e")
    }
}

@Suite struct TranscriptInfoTests {
    @Test func extractsLatestFieldsInOnePass() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("s.jsonl")
        let lines = [
            #"{"type":"permission-mode","permissionMode":"default"}"#,
            #"{"type":"user","cwd":"/old","entrypoint":"cli","message":{"role":"user","content":"eski soru"}}"#,
            #"{"type":"ai-title","aiTitle":"Başlık"}"#,
            #"{"type":"assistant","message":{"model":"claude-opus-5","content":[]}}"#,
            #"{"type":"permission-mode","permissionMode":"bypassPermissions"}"#,
            #"{"type":"user","cwd":"/Users/alice/proj","entrypoint":"cli","message":{"role":"user","content":[{"type":"text","text":"yeni soru\nikinci satır"}]}}"#,
            #"{"type":"user","cwd":"/Users/alice/proj","message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}"#,
            #"{"type":"user","cwd":"/Users/alice/proj","isMeta":true,"message":{"role":"user","content":"<command-name>/clear</command-name>"}}"#,
            #"{"type":"assistant","message":{"model":"<synthetic>","content":[]}}"#,
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)

        let info = try #require(Transcript.info(at: file))
        #expect(info.aiTitle == "Başlık")
        #expect(info.lastPrompt == "yeni soru\nikinci satır")
        #expect(info.model == "claude-opus-5")
        #expect(info.cwd == "/Users/alice/proj")
        #expect(info.entrypoint == "cli")
        #expect(info.permissionMode == "bypassPermissions")
        #expect(info.sizeBytes > 0)
        #expect(info.modified != nil)
    }

    @Test func lastPromptRecordWinsWhenNewer() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("s.jsonl")
        try ([
            #"{"type":"user","cwd":"/a","message":{"content":"önceki"}}"#,
            #"{"type":"last-prompt","lastPrompt":"makineye erişimim varmı"}"#,
            #"{"type":"user","cwd":"/a","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#,
        ].joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        #expect(Transcript.info(at: file)?.lastPrompt == "makineye erişimim varmı")
    }

    @Test func missingFileYieldsNil() {
        #expect(Transcript.info(at: URL(fileURLWithPath: "/nonexistent-\(UUID()).jsonl")) == nil)
    }

    @Test func permissionModeToFlags() {
        #expect(ResumeCommand.flags(permissionMode: "bypassPermissions") == ["--dangerously-skip-permissions"])
        #expect(ResumeCommand.flags(permissionMode: "acceptEdits") == ["--permission-mode", "acceptEdits"])
        #expect(ResumeCommand.flags(permissionMode: "default") == [])
        #expect(ResumeCommand.flags(permissionMode: nil) == [])
    }
}

@Suite struct TranscriptCacheTests {
    @Test func rereadsOnlyWhenFileChanges() throws {
        let projects = try makeTempDir()
        let dir = projects.appendingPathComponent("-Users-alice", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("s1.jsonl")
        try #"{"type":"ai-title","aiTitle":"Bir"}"#.write(to: file, atomically: true, encoding: .utf8)

        var reads = 0
        var now = Date(timeIntervalSince1970: 1_000_000)
        let cache = TranscriptCache(minRereadInterval: 15, clock: { now }) { url in
            reads += 1
            return Transcript.info(at: url)
        }
        let r = SessionRecord(pid: 1, sessionId: "s1", cwd: "/Users/alice")

        #expect(cache.info(for: r, projectsDir: projects)?.aiTitle == "Bir")
        #expect(cache.info(for: r, projectsDir: projects)?.aiTitle == "Bir")
        #expect(reads == 1)

        try #"{"type":"ai-title","aiTitle":"İki"}"#.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: file.path)
        // Changed, but inside the re-read interval → cached value.
        #expect(cache.info(for: r, projectsDir: projects)?.aiTitle == "Bir")
        #expect(reads == 1)

        now = now.addingTimeInterval(16)
        #expect(cache.info(for: r, projectsDir: projects)?.aiTitle == "İki")
        #expect(reads == 2)
        #expect(cache.info(at: file)?.aiTitle == "İki")
        #expect(reads == 2)
    }
}
