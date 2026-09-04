import Domain
import Foundation
import SyncProtocol
import Testing

@Suite("Snapshot protocol")
struct SnapshotCodecTests {
    @Test("round trips stable JSON")
    func roundTrip() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-07-20T09:00:00Z"))
        let original = UsageSnapshot(
            generatedAt: date,
            providers: [
                ProviderSnapshot(
                    id: "codex",
                    displayName: "Codex",
                    sourceUpdatedAt: date,
                    freshness: .fresh,
                    usage: TokenUsage(totalTokens: 123),
                    windows: [QuotaWindow(id: "w", label: "5h", usedPercent: 10, resetAt: date)]
                ),
            ],
            resetEvents: [
                QuotaResetEvent(
                    id: "codex.w.1900000000",
                    providerID: "codex",
                    providerName: "Codex",
                    windowID: "w",
                    windowLabel: "5h",
                    detectedAt: date,
                    expiresAt: date.addingTimeInterval(86_400),
                    previousUsedPercent: 80,
                    currentUsedPercent: 1,
                    previousResetAt: date.addingTimeInterval(-18_000),
                    currentResetAt: date.addingTimeInterval(18_000)
                ),
            ]
        )
        let encoded = try SnapshotCodec.encode(original)
        #expect(try SnapshotCodec.decode(encoded) == original)
    }

    @Test("decodes version 1 snapshots created before reset events were added")
    func legacySnapshotWithoutResetEvents() throws {
        let data = Data(#"{"schemaVersion":1,"generatedAt":"2026-07-20T09:00:00Z","providers":[]}"#.utf8)
        let decoded = try SnapshotCodec.decode(data)
        #expect(decoded.resetEvents.isEmpty)
    }

    @Test("expiry uses inclusive boundary")
    func expiry() {
        let now = Date(timeIntervalSince1970: 2_000)
        let envelope = SnapshotEnvelope(
            deviceId: "mac-test",
            createdAt: now.addingTimeInterval(-60),
            expiresAt: now,
            payload: UsageSnapshot(generatedAt: now, providers: [])
        )
        #expect(envelope.isExpired(at: now))
    }
}
