import Foundation
import Testing
@testable import DeckCore

func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("deckcore-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite struct RegistryReaderTests {
    let sample = """
    {"pid":1597,"sessionId":"3f2c9a1e-7b4d-4e8f-9a21-5c6d7e8f9012","cwd":"/Users/alice","startedAt":1788180553812,"procStart":"Sun Aug 30 07:19:16 2026","version":"2.1.251","peerProtocol":1,"kind":"interactive","entrypoint":"cli","name":"alice-fd","nameSource":"derived","status":"idle","updatedAt":1788533862460}
    """

    @Test func readsOnlyPidJsonFiles() throws {
        let dir = try makeTempDir()
        try sample.write(to: dir.appendingPathComponent("1597.json"), atomically: true, encoding: .utf8)
        try "secret".write(to: dir.appendingPathComponent("1597.abc.key"), atomically: true, encoding: .utf8)
        try sample.write(to: dir.appendingPathComponent("bozuk.json"), atomically: true, encoding: .utf8)
        try "{".write(to: dir.appendingPathComponent("42.json"), atomically: true, encoding: .utf8)

        let records = RegistryReader.read(dir: dir)

        #expect(records.count == 1)
        let r = try #require(records.first)
        #expect(r.pid == 1597)
        #expect(r.sessionId == "3f2c9a1e-7b4d-4e8f-9a21-5c6d7e8f9012")
        #expect(r.cwd == "/Users/alice")
        #expect(r.status == "idle")
        #expect(r.nameSource == "derived")
        #expect(r.updatedAt == 1788533862460)
    }

    @Test func missingDirectoryYieldsEmpty() {
        let records = RegistryReader.read(dir: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        #expect(records.isEmpty)
    }

    @Test func parsesProcStartAsUTC() throws {
        let date = try #require(SessionRecord.parseProcStart("Sun Aug 30 07:19:16 2026"))
        let expected = ISO8601DateFormatter().date(from: "2026-08-30T07:19:16Z")
        #expect(date == expected)
    }

    @Test func parsesProcStartWithPaddedDay() throws {
        let date = try #require(SessionRecord.parseProcStart("Tue Sep  1 09:05:00 2026"))
        let expected = ISO8601DateFormatter().date(from: "2026-09-01T09:05:00Z")
        #expect(date == expected)
    }

    @Test func deckPathsHonorEnvOverrides() {
        let home = URL(fileURLWithPath: "/Users/test")
        let paths = DeckPaths(env: ["CLAUDE_DECK_SESSIONS_DIR": "/x", "CLAUDE_DECK_CLAUDE_BIN": "/tmp/fake"], home: home)
        #expect(paths.sessionsDir.path == "/x")
        #expect(paths.projectsDir.path == "/Users/test/.claude/projects")
        #expect(paths.stateDir.path == "/Users/test/Library/Application Support/ClaudeDeck")
        #expect(paths.claudeBin == "/tmp/fake")
        #expect(DeckPaths(env: [:], home: home).claudeBin == "claude")
    }
}
