import Darwin
import Domain
import Foundation

/// A privacy-minimizing, read-only collector for Codex rollout logs.
///
/// Only `turn_context` model identifiers, the last working-directory component,
/// and `token_count` counters are decoded. Full paths, prompts, responses,
/// tool calls, and credentials are never retained in the resulting snapshot.
public struct CodexLogCollector: Sendable {
    public enum CollectorError: Error, Equatable {
        case directoryNotReadable
    }

    private static let indexVersion = 1
    private static let prefixFingerprintBytes = 4096
    private static let tokenCountNeedle = Array("token_count".utf8)
    private static let turnContextNeedle = Array("turn_context".utf8)
    private static let forkedFromNeedle = Array("forked_from_id".utf8)
    private static let fractionalTimestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let timestampStyle = Date.ISO8601FormatStyle()

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// `cacheDirectory` is intentionally opt-in so package tests and one-shot tools
    /// stay side-effect free. The Mac app supplies its private Application Support
    /// directory, which enables persistent per-file incremental parsing.
    public func fetchSnapshot(
        codexDirectory: URL,
        now: Date = Date(),
        cacheDirectory: URL? = nil
    ) async throws -> UsageSnapshot {
        guard FileManager.default.isReadableFile(atPath: codexDirectory.path) else {
            throw CollectorError.directoryNotReadable
        }

        let indexURL = cacheDirectory?.appending(
            path: "codex-usage-index-v\(Self.indexVersion).json",
            directoryHint: .notDirectory
        )
        let aggregate = try Self.collectAggregate(
            in: codexDirectory,
            calendar: calendar,
            indexURL: indexURL
        )
        return Self.makeSnapshot(aggregate: aggregate, now: now, calendar: calendar)
    }

    /// Kept as a small test seam for fixture-based regression tests.
    static func makeSnapshot(
        samples: [TokenSample],
        now: Date,
        calendar: Calendar
    ) -> UsageSnapshot {
        var aggregate = UsageAggregate()
        for sample in samples {
            aggregate.record(sample, calendar: calendar)
        }
        return makeSnapshot(aggregate: aggregate, now: now, calendar: calendar)
    }

    private static func makeSnapshot(
        aggregate: UsageAggregate,
        now: Date,
        calendar: Calendar
    ) -> UsageSnapshot {
        let today = calendar.startOfDay(for: now)
        let last7Days = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let last30Days = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let dailyStart = calendar.date(byAdding: .day, value: -181, to: today) ?? today
        let todayKey = dayKey(for: today, calendar: calendar)
        let last7Key = dayKey(for: last7Days, calendar: calendar)
        let last30Key = dayKey(for: last30Days, calendar: calendar)
        let dailyStartKey = dayKey(for: dailyStart, calendar: calendar)

        let periods = makePeriods(
            daily: aggregate.daily,
            todayKey: todayKey,
            last7Key: last7Key,
            last30Key: last30Key,
            today: today,
            last7Days: last7Days,
            last30Days: last30Days,
            now: now,
            calendar: calendar
        )

        var modelTotals: [String: Int64] = [:]
        for (key, value) in aggregate.modelDaily
            where key.day >= last30Key && key.day <= todayKey {
            modelTotals[key.model, default: 0] += value
        }

        var projectDailyByName: [String: [String: TokenUsage]] = [:]
        for (key, usage) in aggregate.projectDaily {
            var days = projectDailyByName[key.project] ?? [:]
            days[key.day] = usage
            projectDailyByName[key.project] = days
        }
        var projectModelsByName: [String: [String: Int64]] = [:]
        for (key, value) in aggregate.projectModels {
            var models = projectModelsByName[key.project] ?? [:]
            models[key.model] = value
            projectModelsByName[key.project] = models
        }

        let projectNames = Set(projectDailyByName.keys)
            .union(projectModelsByName.keys)
        let projects = projectNames.map { name in
            let daily = projectDailyByName[name] ?? [:]
            let projectPeriods = makePeriods(
                daily: daily,
                todayKey: todayKey,
                last7Key: last7Key,
                last30Key: last30Key,
                today: today,
                last7Days: last7Days,
                last30Days: last30Days,
                now: now,
                calendar: calendar
            )
            let projectDaily = daily.compactMap { day, usage -> DailyTokenUsage? in
                guard day >= dailyStartKey && day <= todayKey else { return nil }
                return DailyTokenUsage(day: day, totalTokens: usage.totalTokens)
            }
            let projectModels = (projectModelsByName[name] ?? [:]).map {
                ModelTokenUsage(model: $0.key, totalTokens: $0.value)
            }
            return ProjectTokenUsage(
                id: projectIdentifier(name),
                displayName: name,
                periods: projectPeriods,
                daily: projectDaily,
                models: projectModels
            )
        }

        let sourceUpdatedAt = aggregate.sourceUpdatedAt ?? now
        let provider = ProviderSnapshot(
            id: "codex",
            displayName: "Codex",
            sourceUpdatedAt: sourceUpdatedAt,
            freshness: Freshness.classify(sourceUpdatedAt: sourceUpdatedAt, now: now),
            usage: periods.last30Days.usage,
            periods: periods,
            availability: .available,
            detail: aggregate.sampleCount == 0 ? "No token_count records found" : nil
        )
        return UsageSnapshot(
            generatedAt: now,
            providers: [provider],
            analytics: UsageAnalytics(
                daily: aggregate.daily.compactMap { day, usage -> DailyTokenUsage? in
                    guard day >= dailyStartKey && day <= todayKey else { return nil }
                    return DailyTokenUsage(day: day, totalTokens: usage.totalTokens)
                },
                models: modelTotals.map {
                    ModelTokenUsage(model: $0.key, totalTokens: $0.value)
                },
                projects: projects
            )
        )
    }

    private static func makePeriods(
        daily: [String: TokenUsage],
        todayKey: String,
        last7Key: String,
        last30Key: String,
        today: Date,
        last7Days: Date,
        last30Days: Date,
        now: Date,
        calendar: Calendar
    ) -> UsagePeriods {
        UsagePeriods(
            timeZoneIdentifier: calendar.timeZone.identifier,
            today: PeriodTokenUsage(
                usage: aggregate(daily, from: todayKey, through: todayKey),
                startsAt: today,
                endsAt: now
            ),
            last7Days: PeriodTokenUsage(
                usage: aggregate(daily, from: last7Key, through: todayKey),
                startsAt: last7Days,
                endsAt: now
            ),
            last30Days: PeriodTokenUsage(
                usage: aggregate(daily, from: last30Key, through: todayKey),
                startsAt: last30Days,
                endsAt: now
            ),
            recordedAllTime: PeriodTokenUsage(
                usage: daily.reduce(.zero) { current, pair in
                    pair.key <= todayKey ? current.adding(pair.value) : current
                },
                startsAt: Date(timeIntervalSince1970: 0),
                endsAt: now
            )
        )
    }

    private static func aggregate(
        _ daily: [String: TokenUsage],
        from start: String,
        through end: String
    ) -> TokenUsage {
        daily.reduce(.zero) { current, pair in
            guard pair.key >= start && pair.key <= end else { return current }
            return current.adding(pair.value)
        }
    }

    private static func projectIdentifier(_ name: String) -> String {
        let normalized = name.precomposedStringWithCanonicalMapping
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : "-" }
        let value = String(normalized).split(separator: "-").joined(separator: "-")
        return "project-" + (value.isEmpty ? "unknown" : value)
    }

    fileprivate static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func collectAggregate(
        in root: URL,
        calendar: Calendar,
        indexURL: URL?
    ) throws -> UsageAggregate {
        let files = try selectedRollouts(in: root)
        var index = indexURL.flatMap(loadIndex)
            .flatMap { cached in
                cached.calendarIdentifier == String(describing: calendar.identifier)
                    && cached.timeZoneIdentifier == calendar.timeZone.identifier
                    ? cached
                    : nil
            }
            ?? CodexUsageIndex(
                version: indexVersion,
                calendarIdentifier: String(describing: calendar.identifier),
                timeZoneIdentifier: calendar.timeZone.identifier,
                files: [:]
            )
        var didChangeIndex = false
        var merged = UsageAggregate()
        var nextFiles: [String: CachedRollout] = [:]
        nextFiles.reserveCapacity(files.count)

        for file in files.sorted(by: { $0.relativePath < $1.relativePath }) {
            let cached = index.files[file.relativePath]
            let result: CachedRollout

            if let cached,
               cached.fileSize == file.fileSize,
               cached.modificationDate == file.modificationDate {
                result = cached
            } else if let cached,
                      // Codex rollout files are append-only. Only strict growth is
                      // eligible for tail parsing; an equal-size modified file is
                      // conservatively rebuilt instead of trusting stale aggregates.
                      cached.fileSize < file.fileSize,
                      cached.completeOffset <= UInt64(cached.fileSize),
                      prefixMatches(cached, url: file.url) {
                var updated = cached
                updated.completeOffset = try parseRollout(
                    file.url,
                    fromOffset: cached.completeOffset,
                    state: &updated.parserState,
                    aggregate: &updated.aggregate,
                    calendar: calendar
                )
                updated.fileSize = file.fileSize
                updated.modificationDate = file.modificationDate
                result = updated
                didChangeIndex = true
            } else {
                var state = RolloutParserState()
                var aggregate = UsageAggregate()
                let completeOffset = try parseRollout(
                    file.url,
                    fromOffset: 0,
                    state: &state,
                    aggregate: &aggregate,
                    calendar: calendar
                )
                let prefixLength = min(prefixFingerprintBytes, max(0, Int(file.fileSize)))
                result = CachedRollout(
                    fileSize: file.fileSize,
                    modificationDate: file.modificationDate,
                    prefixLength: prefixLength,
                    prefixFingerprint: try prefixFingerprint(file.url, count: prefixLength),
                    completeOffset: completeOffset,
                    parserState: state,
                    aggregate: aggregate
                )
                didChangeIndex = true
            }

            nextFiles[file.relativePath] = result
            merged.merge(result.aggregate)
        }

        if nextFiles.count != index.files.count || Set(nextFiles.keys) != Set(index.files.keys) {
            didChangeIndex = true
        }
        index.files = nextFiles
        if didChangeIndex, let indexURL {
            try? saveIndex(index, to: indexURL)
        }
        return merged
    }

    private static func selectedRollouts(in root: URL) throws -> [RolloutFile] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw CollectorError.directoryNotReadable
        }

        var selectedBySession: [String: RolloutFile] = [:]
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            let values = try? fileURL.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            let modificationDate = values?.contentModificationDate ?? .distantPast
            let relativePath = relativePath(of: fileURL, under: root)
            let file = RolloutFile(
                url: fileURL,
                relativePath: relativePath,
                fileSize: Int64(values?.fileSize ?? 0),
                modificationDate: modificationDate
            )
            let sessionID = sessionIdentifier(for: fileURL)
            if let existing = selectedBySession[sessionID],
               existing.modificationDate >= modificationDate {
                continue
            }
            selectedBySession[sessionID] = file
        }
        return Array(selectedBySession.values)
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func sessionIdentifier(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: "-")
        if parts.count >= 5 {
            return parts.suffix(5).joined(separator: "-")
        }
        return url.path
    }

    private static func parseRollout(
        _ url: URL,
        fromOffset: UInt64,
        state: inout RolloutParserState,
        aggregate: inout UsageAggregate,
        calendar: Calendar
    ) throws -> UInt64 {
        guard let file = fopen(url.path, "rb") else {
            throw CollectorError.directoryNotReadable
        }
        defer { fclose(file) }
        guard fseeko(file, off_t(fromOffset), SEEK_SET) == 0 else {
            throw CollectorError.directoryNotReadable
        }

        var linePointer: UnsafeMutablePointer<CChar>?
        var lineCapacity = 0
        defer { free(linePointer) }
        var completeOffset = fromOffset

        while true {
            errno = 0
            let rawCount = getline(&linePointer, &lineCapacity, file)
            if rawCount < 0 {
                if ferror(file) != 0 { throw CollectorError.directoryNotReadable }
                break
            }
            guard let linePointer else { continue }
            let count = Int(rawCount)
            let hasNewline = count > 0 && linePointer[count - 1] == 0x0A
            let contentCount = hasNewline ? count - 1 : count
            let relevant = containsRelevantBytes(
                UnsafeRawPointer(linePointer),
                count: contentCount
            )

            var validFinalLine = true
            if relevant || !hasNewline {
                let data = Data(bytes: linePointer, count: contentCount)
                validFinalLine = processLine(
                    data,
                    isRelevant: relevant,
                    state: &state,
                    aggregate: &aggregate,
                    calendar: calendar,
                    validateIrrelevant: !hasNewline
                )
            }

            if hasNewline || validFinalLine {
                let position = ftello(file)
                if position >= 0 { completeOffset = UInt64(position) }
            }
        }
        return completeOffset
    }

    @discardableResult
    private static func processLine(
        _ data: Data,
        isRelevant: Bool,
        state: inout RolloutParserState,
        aggregate: inout UsageAggregate,
        calendar: Calendar,
        validateIrrelevant: Bool
    ) -> Bool {
        if !isRelevant && !validateIrrelevant { return true }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        guard isRelevant else { return true }
        guard let payload = object["payload"] as? [String: Any] else { return true }

        if object["type"] as? String == "turn_context" {
            if let nextModel = payload["model"] as? String, !nextModel.isEmpty {
                state.model = nextModel
            }
            if let cwd = payload["cwd"] as? String {
                let folder = URL(fileURLWithPath: cwd).standardizedFileURL.lastPathComponent
                if !folder.isEmpty && folder != "/" && folder != "." {
                    state.projectName = folder
                }
            }
            return true
        }
        if object["type"] as? String == "session_meta",
           let parent = payload["forked_from_id"] as? String,
           !parent.isEmpty {
            state.isForkedSession = true
            return true
        }

        let tokenPayload: [String: Any]?
        if payload["type"] as? String == "token_count" {
            tokenPayload = payload
        } else if let message = payload["msg"] as? [String: Any],
                  message["type"] as? String == "token_count" {
            tokenPayload = message
        } else {
            tokenPayload = nil
        }
        guard let info = tokenPayload?["info"] as? [String: Any],
              let timestampText = object["timestamp"] as? String,
              let timestamp = parseTimestamp(timestampText) else {
            return true
        }

        let last = (info["last_token_usage"] as? [String: Any]).map(UsageCounters.init)
        let total = (info["total_token_usage"] as? [String: Any]).map(UsageCounters.init)
        guard let delta = UsageCounters.delta(last: last, total: total, previous: state.previousTotal),
              delta.totalTokens > 0 else {
            if let total { state.previousTotal = total }
            return true
        }
        if let total { state.previousTotal = total }

        if state.isForkedSession && state.forkReplayPrefixActive {
            let previousTimestamp = state.previousForkTokenTimestamp
            state.previousForkTokenTimestamp = timestamp
            guard let previousTimestamp else { return true }
            if timestamp.timeIntervalSince(previousTimestamp) < 2 { return true }
            state.forkReplayPrefixActive = false
        }

        aggregate.record(
            TokenSample(
                timestamp: timestamp,
                model: state.model,
                projectName: state.projectName,
                usage: delta.domainValue
            ),
            calendar: calendar
        )
        return true
    }

    private static func containsRelevantBytes(_ pointer: UnsafeRawPointer, count: Int) -> Bool {
        contains(tokenCountNeedle, in: pointer, count: count)
            || contains(turnContextNeedle, in: pointer, count: count)
            || contains(forkedFromNeedle, in: pointer, count: count)
    }

    private static func contains(
        _ needle: [UInt8],
        in pointer: UnsafeRawPointer,
        count: Int
    ) -> Bool {
        guard count >= needle.count else { return false }
        return needle.withUnsafeBytes { needleBytes in
            memmem(pointer, count, needleBytes.baseAddress, needleBytes.count) != nil
        }
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        (try? fractionalTimestampStyle.parse(value))
            ?? (try? timestampStyle.parse(value))
    }

    private static func prefixMatches(_ cached: CachedRollout, url: URL) -> Bool {
        guard cached.prefixLength >= 0 else { return false }
        return (try? prefixFingerprint(url, count: cached.prefixLength)) == cached.prefixFingerprint
    }

    private static func prefixFingerprint(_ url: URL, count: Int) throws -> UInt64 {
        guard count > 0 else { return 0 }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { return UInt64.max }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private static func loadIndex(_ url: URL) -> CodexUsageIndex? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let index = try? decoder.decode(CodexUsageIndex.self, from: data),
              index.version == indexVersion else { return nil }
        return index
    }

    private static func saveIndex(_ index: CodexUsageIndex, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(index)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}

struct TokenSample: Equatable, Sendable {
    let timestamp: Date
    let model: String
    let projectName: String
    let usage: TokenUsage
}

private struct RolloutFile {
    let url: URL
    let relativePath: String
    let fileSize: Int64
    let modificationDate: Date
}

private struct CodexUsageIndex: Codable {
    let version: Int
    let calendarIdentifier: String
    let timeZoneIdentifier: String
    var files: [String: CachedRollout]
}

private struct CachedRollout: Codable {
    var fileSize: Int64
    var modificationDate: Date
    var prefixLength: Int
    var prefixFingerprint: UInt64
    var completeOffset: UInt64
    var parserState: RolloutParserState
    var aggregate: UsageAggregate
}

private struct RolloutParserState: Codable {
    var model = "Unknown Codex model"
    var projectName = "Unknown Project"
    var previousTotal: UsageCounters?
    var isForkedSession = false
    var forkReplayPrefixActive = true
    var previousForkTokenTimestamp: Date?
}

private struct ModelDayKey: Hashable, Codable {
    let model: String
    let day: String
}

private struct ProjectDayKey: Hashable, Codable {
    let project: String
    let day: String
}

private struct ProjectModelKey: Hashable, Codable {
    let project: String
    let model: String
}

private struct UsageAggregate: Codable {
    var sourceUpdatedAt: Date?
    var sampleCount = 0
    var daily: [String: TokenUsage] = [:]
    var modelDaily: [ModelDayKey: Int64] = [:]
    var projectDaily: [ProjectDayKey: TokenUsage] = [:]
    var projectModels: [ProjectModelKey: Int64] = [:]

    mutating func record(_ sample: TokenSample, calendar: Calendar) {
        let day = CodexLogCollector.dayKey(for: sample.timestamp, calendar: calendar)
        sourceUpdatedAt = max(sourceUpdatedAt ?? sample.timestamp, sample.timestamp)
        sampleCount += 1
        daily[day] = (daily[day] ?? .zero).adding(sample.usage)
        modelDaily[ModelDayKey(model: sample.model, day: day), default: 0]
            += sample.usage.totalTokens

        let projectDay = ProjectDayKey(project: sample.projectName, day: day)
        projectDaily[projectDay] = (projectDaily[projectDay] ?? .zero).adding(sample.usage)
        projectModels[ProjectModelKey(project: sample.projectName, model: sample.model), default: 0]
            += sample.usage.totalTokens
    }

    mutating func merge(_ other: Self) {
        if let date = other.sourceUpdatedAt {
            sourceUpdatedAt = max(sourceUpdatedAt ?? date, date)
        }
        sampleCount += other.sampleCount
        for (day, usage) in other.daily {
            daily[day] = (daily[day] ?? .zero).adding(usage)
        }
        for (key, value) in other.modelDaily {
            modelDaily[key, default: 0] += value
        }
        for (key, usage) in other.projectDaily {
            projectDaily[key] = (projectDaily[key] ?? .zero).adding(usage)
        }
        for (key, value) in other.projectModels {
            projectModels[key, default: 0] += value
        }
    }
}

private struct UsageCounters: Equatable, Codable {
    let input: Int64
    let output: Int64
    let cachedInput: Int64
    let reasoningOutput: Int64
    let totalTokens: Int64

    init(_ object: [String: Any]) {
        input = Self.integer(object["input_tokens"])
        output = Self.integer(object["output_tokens"])
        cachedInput = Self.integer(object["cached_input_tokens"])
        reasoningOutput = Self.integer(object["reasoning_output_tokens"])
        let reportedTotal = Self.integer(object["total_tokens"])
        totalTokens = reportedTotal > 0 ? reportedTotal : input + output
    }

    static func delta(
        last: Self?,
        total: Self?,
        previous: Self?
    ) -> Self? {
        if let total, let previous {
            if total.totalTokens < previous.totalTokens {
                return last ?? total
            }
            let delta = total.subtracting(previous)
            return delta.totalTokens > 0 ? delta : nil
        }
        return last ?? total
    }

    var domainValue: TokenUsage {
        TokenUsage(
            measurement: .incremental,
            inputTokens: input,
            outputTokens: output,
            cachedInputTokens: cachedInput,
            reasoningOutputTokens: reasoningOutput,
            totalTokens: totalTokens
        )
    }

    private func subtracting(_ other: Self) -> Self {
        Self(
            input: max(0, input - other.input),
            output: max(0, output - other.output),
            cachedInput: max(0, cachedInput - other.cachedInput),
            reasoningOutput: max(0, reasoningOutput - other.reasoningOutput),
            totalTokens: max(0, totalTokens - other.totalTokens)
        )
    }

    private init(
        input: Int64,
        output: Int64,
        cachedInput: Int64,
        reasoningOutput: Int64,
        totalTokens: Int64
    ) {
        self.input = input
        self.output = output
        self.cachedInput = cachedInput
        self.reasoningOutput = reasoningOutput
        self.totalTokens = totalTokens
    }

    private static func integer(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return max(0, number.int64Value) }
        if let string = value as? String, let number = Int64(string) { return max(0, number) }
        return 0
    }
}

private extension TokenUsage {
    static let zero = TokenUsage(totalTokens: 0)

    func adding(_ other: Self) -> Self {
        Self(
            measurement: .aggregate,
            isKnown: isKnown || other.isKnown,
            inputTokens: inputTokens + other.inputTokens,
            outputTokens: outputTokens + other.outputTokens,
            cachedInputTokens: cachedInputTokens + other.cachedInputTokens,
            reasoningOutputTokens: reasoningOutputTokens + other.reasoningOutputTokens,
            totalTokens: totalTokens + other.totalTokens
        )
    }
}
