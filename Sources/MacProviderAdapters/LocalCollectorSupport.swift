import Darwin
import Domain
import Foundation

struct LocalFileStamp: Equatable, Sendable {
    let path: String
    let fileSize: Int64
    let modificationDate: Date
}

enum LocalCollectorSupport {
    static let fractionalTimestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    static let timestampStyle = Date.ISO8601FormatStyle()

    static func parseTimestamp(_ value: String) -> Date? {
        (try? fractionalTimestampStyle.parse(value))
            ?? (try? timestampStyle.parse(value))
    }

    static func fileStamp(_ url: URL, relativeTo root: URL) -> LocalFileStamp? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true else {
            return nil
        }
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let relativePath = path.hasPrefix(rootPath + "/")
            ? String(path.dropFirst(rootPath.count + 1))
            : url.lastPathComponent
        return LocalFileStamp(
            path: relativePath,
            fileSize: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate ?? .distantPast
        )
    }

    static func refreshedSnapshot(_ snapshot: UsageSnapshot, at now: Date) -> UsageSnapshot {
        UsageSnapshot(
            schemaVersion: snapshot.schemaVersion,
            generatedAt: now,
            providers: snapshot.providers.map { provider in
                let periods = UsagePeriods(
                    timeZoneIdentifier: provider.periods.timeZoneIdentifier,
                    today: refreshedPeriod(provider.periods.today, at: now),
                    last7Days: refreshedPeriod(provider.periods.last7Days, at: now),
                    last30Days: refreshedPeriod(provider.periods.last30Days, at: now),
                    recordedAllTime: refreshedPeriod(provider.periods.recordedAllTime, at: now)
                )
                return ProviderSnapshot(
                    id: provider.id,
                    displayName: provider.displayName,
                    sourceUpdatedAt: provider.sourceUpdatedAt,
                    freshness: provider.availability == .available
                        ? Freshness.classify(sourceUpdatedAt: provider.sourceUpdatedAt, now: now)
                        : .offline,
                    usage: periods.last30Days.usage,
                    periods: periods,
                    windows: provider.windows,
                    availability: provider.availability,
                    detail: provider.detail,
                    sourceKind: provider.sourceKind,
                    planName: provider.planName,
                    isEstimated: provider.isEstimated
                )
            },
            analytics: snapshot.analytics,
            resetEvents: snapshot.resetEvents,
            mode: snapshot.mode
        )
    }

    private static func refreshedPeriod(_ period: PeriodTokenUsage, at now: Date) -> PeriodTokenUsage {
        PeriodTokenUsage(usage: period.usage, startsAt: period.startsAt, endsAt: now)
    }
}

enum JSONLStreamReader {
    static func forEachLine(
        at url: URL,
        containingAny needles: [[UInt8]] = [],
        _ body: (Data, Int) throws -> Void
    ) throws {
        guard let file = fopen(url.path, "rb") else {
            throw CocoaError(.fileReadNoPermission)
        }
        defer { fclose(file) }

        var linePointer: UnsafeMutablePointer<CChar>?
        var capacity = 0
        defer { free(linePointer) }
        var lineIndex = 0

        while true {
            errno = 0
            let rawCount = getline(&linePointer, &capacity, file)
            if rawCount < 0 {
                if ferror(file) != 0 { throw CocoaError(.fileReadUnknown) }
                break
            }
            guard let linePointer else { continue }
            var count = Int(rawCount)
            if count > 0 && linePointer[count - 1] == 0x0A { count -= 1 }
            if count > 0 && linePointer[count - 1] == 0x0D { count -= 1 }
            defer { lineIndex += 1 }
            guard count > 0 else { continue }
            if !needles.isEmpty,
               !needles.contains(where: { contains($0, pointer: linePointer, count: count) }) {
                continue
            }
            try body(Data(bytes: linePointer, count: count), lineIndex)
        }
    }

    private static func contains(
        _ needle: [UInt8],
        pointer: UnsafeRawPointer,
        count: Int
    ) -> Bool {
        guard !needle.isEmpty, count >= needle.count else { return false }
        return needle.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return false }
            return memmem(pointer, count, baseAddress, bytes.count) != nil
        }
    }
}
