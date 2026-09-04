import Domain
import Foundation
import MacProviderAdapters
import SQLite3
import Testing

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@Suite("OpenCode log collector")
struct OpenCodeLogCollectorTests {
    @Test("reads v1 and v2 SQLite message shapes")
    func readsSQLite() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "tokenwatch-opencode-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databaseURL = root.appending(path: "opencode.db")
        try createFixtureDatabase(databaseURL)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")!
        let snapshot = try await OpenCodeLogCollector(calendar: calendar)
            .fetchSnapshot(openCodeDirectory: root, now: now)
        let provider = try #require(snapshot.providers.first)
        let analytics = try #require(snapshot.analytics)

        #expect(provider.id == "opencode")
        #expect(provider.periods.today.usage.inputTokens == 30)
        #expect(provider.periods.today.usage.outputTokens == 11)
        #expect(provider.periods.today.usage.cachedInputTokens == 6)
        #expect(provider.periods.today.usage.reasoningOutputTokens == 3)
        #expect(provider.periods.today.usage.totalTokens == 50)
        #expect(Set(analytics.models.map(\.model)) == ["model-v1", "model-v2"])
        #expect(analytics.projects.first?.displayName == "ProjectA")
    }

    @Test("reads legacy JSON message storage when SQLite is absent")
    func readsLegacyJSON() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "tokenwatch-opencode-legacy-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let messages = root
            .appending(path: "storage/message/session-1", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: messages, withIntermediateDirectories: true)

        let json = #"{"id":"legacy-1","role":"assistant","modelID":"legacy-model","time":{"created":1788429720000},"path":{"cwd":"/Users/test/LegacyProject"},"tokens":{"input":12,"output":4,"reasoning":2,"cache":{"read":3,"write":1}}}"#
        try Data(json.utf8).write(to: messages.appending(path: "legacy-1.json"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")!
        let snapshot = try await OpenCodeLogCollector(calendar: calendar)
            .fetchSnapshot(openCodeDirectory: root, now: now)
        let provider = try #require(snapshot.providers.first)
        let analytics = try #require(snapshot.analytics)

        #expect(provider.periods.today.usage.inputTokens == 12)
        #expect(provider.periods.today.usage.outputTokens == 4)
        #expect(provider.periods.today.usage.cachedInputTokens == 4)
        #expect(provider.periods.today.usage.reasoningOutputTokens == 2)
        #expect(provider.periods.today.usage.totalTokens == 22)
        #expect(analytics.models.first?.model == "legacy-model")
        #expect(analytics.projects.first?.displayName == "LegacyProject")
    }

    @Test("legacy fingerprint fast path invalidates when a message is added")
    func legacyFingerprintInvalidates() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "tokenwatch-opencode-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let messages = root.appending(path: "storage/message", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: messages, withIntermediateDirectories: true)
        let first = #"{"id":"legacy-1","role":"assistant","modelID":"legacy-model","time":{"created":1788429720000},"path":{"cwd":"/Users/test/LegacyProject"},"tokens":{"input":12,"output":4,"reasoning":2,"cache":{"read":3,"write":1}}}"#
        try Data(first.utf8).write(to: messages.appending(path: "legacy-1.json"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")!
        let collector = OpenCodeLogCollector(calendar: calendar)
        let initial = try await collector.fetchSnapshot(openCodeDirectory: root, now: now)
        #expect(initial.providers.first?.periods.today.usage.totalTokens == 22)

        let second = #"{"id":"legacy-2","role":"assistant","modelID":"legacy-model","time":{"created":1788429780000},"path":{"cwd":"/Users/test/LegacyProject"},"tokens":{"input":8,"output":2,"reasoning":0,"cache":{"read":0,"write":0}}}"#
        try Data(second.utf8).write(to: messages.appending(path: "legacy-2.json"))
        let updated = try await collector.fetchSnapshot(openCodeDirectory: root, now: now)
        #expect(updated.providers.first?.periods.today.usage.totalTokens == 32)
        let stable = try await collector.fetchSnapshot(
            openCodeDirectory: root,
            now: now.addingTimeInterval(60)
        )
        #expect(stable.providers.first?.periods.today.usage.totalTokens == 32)
    }

    @Test("database fingerprint fast path invalidates after SQLite update")
    func databaseFingerprintInvalidates() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "tokenwatch-opencode-db-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databaseURL = root.appending(path: "opencode.db")
        try createFixtureDatabase(databaseURL)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")!
        let collector = OpenCodeLogCollector(calendar: calendar)
        let first = try await collector.fetchSnapshot(openCodeDirectory: root, now: now)
        #expect(first.providers.first?.periods.today.usage.totalTokens == 50)

        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
            throw FixtureError.sqlite
        }
        let third = #"{"id":"m3","sessionID":"s1","role":"assistant","modelID":"model-v3","time":{"created":1788429720000},"tokens":{"input":9,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}"#
        try insert(
            db,
            table: "message",
            id: "m3",
            session: "s1",
            timestamp: 1_788_429_720_000,
            json: third
        )
        sqlite3_close(db)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(5)],
            ofItemAtPath: databaseURL.path
        )

        let second = try await collector.fetchSnapshot(openCodeDirectory: root, now: now)
        #expect(second.providers.first?.periods.today.usage.totalTokens == 60)
        let stable = try await collector.fetchSnapshot(
            openCodeDirectory: root,
            now: now.addingTimeInterval(60)
        )
        #expect(stable.providers.first?.periods.today.usage.totalTokens == 60)
    }

    private func createFixtureDatabase(_ url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw FixtureError.sqlite
        }
        defer { sqlite3_close(db) }
        try exec(db, "CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT NOT NULL)")
        try exec(db, "CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT)")
        try exec(db, "CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT, type TEXT, seq INTEGER, time_created INTEGER, time_updated INTEGER, data TEXT)")
        try exec(db, "INSERT INTO session VALUES ('s1', '/Users/test/ProjectA')")
        let first = #"{"id":"m1","sessionID":"s1","role":"assistant","modelID":"model-v1","providerID":"test","time":{"created":1788429600000},"tokens":{"input":10,"output":5,"reasoning":0,"cache":{"read":2,"write":1}}}"#
        let second = #"{"id":"m2","sessionID":"s1","type":"assistant","model":{"id":"model-v2","providerID":"test"},"time":{"created":1788429660000},"tokens":{"input":20,"output":6,"reasoning":3,"cache":{"read":1,"write":2}}}"#
        try insert(db, table: "message", id: "m1", session: "s1", timestamp: 1_788_429_600_000, json: first)
        try insert(db, table: "session_message", id: "m2", session: "s1", timestamp: 1_788_429_660_000, json: second)
    }

    private func insert(
        _ db: OpaquePointer,
        table: String,
        id: String,
        session: String,
        timestamp: Int64,
        json: String
    ) throws {
        let sql: String
        if table == "session_message" {
            sql = "INSERT INTO session_message (id, session_id, type, seq, time_created, time_updated, data) VALUES (?, ?, 'assistant', 0, ?, ?, ?)"
        } else {
            sql = "INSERT INTO message (id, session_id, time_created, time_updated, data) VALUES (?, ?, ?, ?, ?)"
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw FixtureError.sqlite }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, session, -1, sqliteTransient)
        sqlite3_bind_int64(statement, 3, timestamp)
        sqlite3_bind_int64(statement, 4, timestamp)
        sqlite3_bind_text(statement, 5, json, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw FixtureError.sqlite }
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw FixtureError.sqlite
        }
    }

    private enum FixtureError: Error { case sqlite }
}
