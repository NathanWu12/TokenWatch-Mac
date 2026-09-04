import Domain
import Foundation
import SQLite3

/// Read-only OpenCode usage reader. Current releases are read from the local
/// SQLite store; legacy JSON message storage is used only as a fallback.
public actor OpenCodeLogCollector {
    public enum CollectorError: Error, Equatable {
        case directoryNotReadable
        case databaseOpenFailed
    }

    private let calendar: Calendar
    private var cachedSourceStamp: OpenCodeSourceStamp?
    private var cachedSnapshot: UsageSnapshot?

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func fetchSnapshot(
        openCodeDirectory: URL,
        now: Date = Date()
    ) async throws -> UsageSnapshot {
        guard FileManager.default.isReadableFile(atPath: openCodeDirectory.path) else {
            throw CollectorError.directoryNotReadable
        }

        let databaseURL = openCodeDirectory.appending(path: "opencode.db", directoryHint: .notDirectory)
        var samples: [LocalUsageSample] = []
        var sourceStamp: OpenCodeSourceStamp
        if FileManager.default.isReadableFile(atPath: databaseURL.path),
           let stamp = LocalCollectorSupport.fileStamp(databaseURL, relativeTo: openCodeDirectory) {
            sourceStamp = .database(stamp)
            if sourceStamp == cachedSourceStamp, let cachedSnapshot {
                return LocalCollectorSupport.refreshedSnapshot(cachedSnapshot, at: now)
            }
            samples = try Self.readDatabase(databaseURL)
        } else {
            sourceStamp = .legacy([])
        }

        if samples.isEmpty {
            let files = Self.legacyMessageFiles(openCodeDirectory)
            sourceStamp = .legacy(files.map(\.stamp))
            if sourceStamp == cachedSourceStamp, let cachedSnapshot {
                return LocalCollectorSupport.refreshedSnapshot(cachedSnapshot, at: now)
            }
            samples = Self.readLegacyMessages(files)
        }

        let snapshot = LocalUsageSnapshotBuilder.makeSnapshot(
            providerID: LocalAIClient.openCode.rawValue,
            displayName: LocalAIClient.openCode.displayName,
            samples: samples,
            now: now,
            calendar: calendar,
            detail: samples.isEmpty ? "No local OpenCode token records found" : nil
        )
        cachedSourceStamp = sourceStamp
        cachedSnapshot = snapshot
        return snapshot
    }

    private static func readDatabase(_ url: URL) throws -> [LocalUsageSample] {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            throw CollectorError.databaseOpenFailed
        }
        defer { sqlite3_close(database) }

        let sessionDirectories = readSessionDirectories(database)
        var candidates: [ParsedMessage] = []
        if tableExists("message", database: database) {
            candidates.append(contentsOf: readMessageTable(
                "message",
                database: database,
                sessionDirectories: sessionDirectories
            ))
        }
        if tableExists("session_message", database: database) {
            candidates.append(contentsOf: readMessageTable(
                "session_message",
                database: database,
                sessionDirectories: sessionDirectories
            ))
        }
        return deduplicate(candidates).map(\.sample)
    }

    private static func readSessionDirectories(_ database: OpaquePointer) -> [String: String] {
        var result: [String: String] = [:]
        for table in ["session", "session_v2"] where tableExists(table, database: database) {
            let columns = columns(in: table, database: database)
            guard columns.contains("id"), columns.contains("directory") else { continue }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "SELECT id, directory FROM \"\(table)\"",
                -1,
                &statement,
                nil
            ) == SQLITE_OK, let statement else { continue }
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = text(statement, column: 0),
                      let directory = text(statement, column: 1),
                      !directory.isEmpty else { continue }
                result[id] = directory
            }
        }
        return result
    }

    private static func readMessageTable(
        _ table: String,
        database: OpaquePointer,
        sessionDirectories: [String: String]
    ) -> [ParsedMessage] {
        let availableColumns = columns(in: table, database: database)
        guard availableColumns.contains("data") else { return [] }
        let idExpression = availableColumns.contains("id") ? "id" : "NULL"
        let sessionExpression = availableColumns.contains("session_id") ? "session_id" : "NULL"
        let timeExpression = availableColumns.contains("time_created") ? "time_created" : "NULL"
        let sql = "SELECT \(idExpression), \(sessionExpression), \(timeExpression), data FROM \"\(table)\""

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }

        var result: [ParsedMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rowID = text(statement, column: 0)
            let sessionID = text(statement, column: 1)
            let fallbackTimestamp = numericTimestamp(statement, column: 2)
            guard let jsonData = data(statement, column: 3),
                  let parsed = parseMessage(
                    jsonData,
                    rowID: rowID,
                    sessionDirectory: sessionID.flatMap { sessionDirectories[$0] },
                    fallbackTimestamp: fallbackTimestamp
                  ) else {
                continue
            }
            result.append(parsed)
        }
        return result
    }

    private static func legacyMessageFiles(_ root: URL) -> [(url: URL, stamp: LocalFileStamp)] {
        var roots: [URL] = []
        let direct = root.appending(path: "storage/message", directoryHint: .isDirectory)
        if isDirectory(direct) { roots.append(direct) }

        let projects = root.appending(path: "project", directoryHint: .isDirectory)
        if let children = try? FileManager.default.contentsOfDirectory(
            at: projects,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in children {
                let messageRoot = child.appending(path: "storage/message", directoryHint: .isDirectory)
                if isDirectory(messageRoot) { roots.append(messageRoot) }
            }
        }

        var files: [(URL, LocalFileStamp)] = []
        for messageRoot in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: messageRoot,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let file as URL in enumerator where file.pathExtension == "json" {
                guard let stamp = LocalCollectorSupport.fileStamp(file, relativeTo: root) else { continue }
                files.append((file, stamp))
            }
        }
        return files.sorted { $0.1.path < $1.1.path }
    }

    private static func readLegacyMessages(
        _ files: [(url: URL, stamp: LocalFileStamp)]
    ) -> [LocalUsageSample] {
        var candidates: [ParsedMessage] = []
        candidates.reserveCapacity(files.count)
        for file in files {
            guard let jsonData = try? Data(contentsOf: file.url, options: .mappedIfSafe),
                  let parsed = parseMessage(
                    jsonData,
                    rowID: file.url.deletingPathExtension().lastPathComponent,
                    sessionDirectory: nil,
                    fallbackTimestamp: nil
                  ) else { continue }
            candidates.append(parsed)
        }
        return deduplicate(candidates).map(\.sample)
    }

    private static func parseMessage(
        _ data: Data,
        rowID: String?,
        sessionDirectory: String?,
        fallbackTimestamp: Date?
    ) -> ParsedMessage? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let role = nonEmptyString(object["role"])
            ?? nonEmptyString(object["type"])
        guard role?.lowercased() == "assistant",
              let tokens = object["tokens"] as? [String: Any] else {
            return nil
        }

        let input = integer(tokens["input"])
        let output = integer(tokens["output"])
        let reasoning = integer(tokens["reasoning"])
        let cache = tokens["cache"] as? [String: Any]
        let cacheRead = integer(cache?["read"])
        let cacheWrite = integer(cache?["write"])
        let cached = cacheRead + cacheWrite
        let total = input + output + reasoning + cached
        guard total > 0 else { return nil }

        let model = modelName(object) ?? "Unknown OpenCode model"
        let timestamp = timestamp(object["time"]) ?? fallbackTimestamp
        guard let timestamp else { return nil }
        let project = projectName(
            sessionDirectory: sessionDirectory,
            object: object
        )
        let usage = TokenUsage(
            measurement: .incremental,
            inputTokens: input,
            outputTokens: output,
            cachedInputTokens: cached,
            reasoningOutputTokens: reasoning,
            totalTokens: total
        )
        let sample = LocalUsageSample(
            timestamp: timestamp,
            model: model,
            projectName: project,
            usage: usage
        )
        let fingerprint = [
            String(Int64(timestamp.timeIntervalSince1970 * 1000)),
            model,
            project,
            String(input),
            String(output),
            String(reasoning),
            String(cacheRead),
            String(cacheWrite),
        ].joined(separator: "|")
        return ParsedMessage(id: rowID, fingerprint: fingerprint, sample: sample)
    }

    private static func modelName(_ object: [String: Any]) -> String? {
        if let model = nonEmptyString(object["modelID"]) { return model }
        if let model = nonEmptyString(object["model"]) { return model }
        if let model = object["model"] as? [String: Any],
           let id = nonEmptyString(model["id"]) {
            return id
        }
        return nil
    }

    private static func projectName(
        sessionDirectory: String?,
        object: [String: Any]
    ) -> String {
        let pathObject = object["path"] as? [String: Any]
        let cwd = sessionDirectory
            ?? nonEmptyString(pathObject?["cwd"])
            ?? nonEmptyString(object["cwd"])
        guard let cwd else { return "Unknown OpenCode Project" }
        let name = URL(fileURLWithPath: cwd).standardizedFileURL.lastPathComponent
        return name.isEmpty ? "Unknown OpenCode Project" : name
    }

    private static func timestamp(_ value: Any?) -> Date? {
        guard let object = value as? [String: Any] else { return nil }
        if let created = object["created"] as? NSNumber {
            return date(fromNumericTimestamp: created.doubleValue)
        }
        if let created = object["created"] as? String {
            if let numeric = Double(created) { return date(fromNumericTimestamp: numeric) }
            return parseISO8601(created)
        }
        return nil
    }

    private static func numericTimestamp(_ statement: OpaquePointer, column: Int32) -> Date? {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER:
            return date(fromNumericTimestamp: Double(sqlite3_column_int64(statement, column)))
        case SQLITE_FLOAT:
            return date(fromNumericTimestamp: sqlite3_column_double(statement, column))
        case SQLITE_TEXT:
            guard let value = text(statement, column: column) else { return nil }
            if let numeric = Double(value) { return date(fromNumericTimestamp: numeric) }
            return parseISO8601(value)
        default:
            return nil
        }
    }

    private static func date(fromNumericTimestamp value: Double) -> Date {
        let seconds = value > 10_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        LocalCollectorSupport.parseTimestamp(value)
    }

    private static func deduplicate(_ values: [ParsedMessage]) -> [ParsedMessage] {
        var seenIDs = Set<String>()
        var seenFingerprints = Set<String>()
        return values
            .sorted { $0.sample.timestamp < $1.sample.timestamp }
            .filter { value in
                if let id = value.id, !id.isEmpty, !seenIDs.insert(id).inserted {
                    return false
                }
                return seenFingerprints.insert(value.fingerprint).inserted
            }
    }

    private static func tableExists(_ table: String, database: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='\(table)' LIMIT 1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func columns(in table: String, database: OpaquePointer) -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "PRAGMA table_info(\"\(table)\")",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var result = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = text(statement, column: 1) { result.insert(name) }
        }
        return result
    }

    private static func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let raw = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: raw)
    }

    private static func data(_ statement: OpaquePointer, column: Int32) -> Data? {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_TEXT:
            guard let string = text(statement, column: column) else { return nil }
            return Data(string.utf8)
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
            let count = Int(sqlite3_column_bytes(statement, column))
            return Data(bytes: bytes, count: count)
        default:
            return nil
        }
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }

    private static func integer(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return max(0, number.int64Value) }
        if let string = value as? String, let number = Int64(string) { return max(0, number) }
        return 0
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            && directory.boolValue
    }
}

private struct ParsedMessage {
    let id: String?
    let fingerprint: String
    let sample: LocalUsageSample
}

private enum OpenCodeSourceStamp: Equatable, Sendable {
    case database(LocalFileStamp)
    case legacy([LocalFileStamp])
}
