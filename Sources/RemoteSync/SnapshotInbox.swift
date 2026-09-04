import Domain
import Foundation
import SyncSecurity

public struct SnapshotInboxState: Codable, Equatable, Sendable {
    public let rememberedMessageIds: [UUID]
    public let latestCreatedAt: Date?

    public init(rememberedMessageIds: [UUID], latestCreatedAt: Date?) {
        self.rememberedMessageIds = rememberedMessageIds
        self.latestCreatedAt = latestCreatedAt
    }
}

public actor SnapshotInbox {
    public enum Decision: Equatable, Sendable {
        case accepted(UsageSnapshot)
        case duplicate
        case outOfOrder
        case expired
    }

    private var seenMessageIds: Set<UUID> = []
    private var order: [UUID] = []
    private var latestCreatedAt: Date?
    private let maximumRememberedMessages: Int

    public init(
        state: SnapshotInboxState? = nil,
        maximumRememberedMessages: Int = 512
    ) {
        self.maximumRememberedMessages = max(32, maximumRememberedMessages)
        let restored = Array(
            (state?.rememberedMessageIds ?? []).suffix(self.maximumRememberedMessages)
        )
        order = restored
        seenMessageIds = Set(restored)
        latestCreatedAt = state?.latestCreatedAt
    }

    public func persistedState() -> SnapshotInboxState {
        SnapshotInboxState(
            rememberedMessageIds: order,
            latestCreatedAt: latestCreatedAt
        )
    }

    public func consume(
        _ envelope: EncryptedSnapshotEnvelope,
        recipientDeviceId: String,
        sharedKeyData: Data,
        now: Date
    ) throws -> Decision {
        if seenMessageIds.contains(envelope.messageId) {
            return .duplicate
        }
        guard !envelope.isExpired(at: now) else {
            remember(envelope.messageId)
            return .expired
        }
        if let latestCreatedAt, envelope.createdAt < latestCreatedAt {
            remember(envelope.messageId)
            return .outOfOrder
        }
        let snapshot = try SnapshotCrypto.open(
            envelope,
            recipientDeviceId: recipientDeviceId,
            sharedKeyData: sharedKeyData,
            now: now
        )
        remember(envelope.messageId)
        latestCreatedAt = envelope.createdAt
        return .accepted(snapshot)
    }

    private func remember(_ messageId: UUID) {
        seenMessageIds.insert(messageId)
        order.append(messageId)
        if order.count > maximumRememberedMessages {
            let overflow = order.count - maximumRememberedMessages
            let removed = order.prefix(overflow)
            seenMessageIds.subtract(removed)
            order.removeFirst(overflow)
        }
    }
}

public protocol SnapshotMailbox: Sendable {
    func saveLatest(_ data: Data, recipientDeviceId: String) async throws
    func fetchLatest(recipientDeviceId: String) async throws -> Data?
    func deleteLatest(recipientDeviceId: String) async throws
}

public struct MailboxChangeBatch: Equatable, Sendable {
    public let latestData: Data?
    public let changeToken: Data

    public init(latestData: Data?, changeToken: Data) {
        self.latestData = latestData
        self.changeToken = changeToken
    }
}

public protocol ChangeTrackingSnapshotMailbox: SnapshotMailbox {
    func installChangeSubscription() async throws
    func fetchChanges(
        recipientDeviceId: String,
        since changeToken: Data?
    ) async throws -> MailboxChangeBatch
}

public actor InMemorySnapshotMailbox: ChangeTrackingSnapshotMailbox {
    private var records: [String: Data] = [:]
    private var versions: [String: UInt64] = [:]

    public init() {}

    public func installChangeSubscription() {}

    public func saveLatest(_ data: Data, recipientDeviceId: String) {
        records[recipientDeviceId] = data
        versions[recipientDeviceId, default: 0] += 1
    }

    public func fetchLatest(recipientDeviceId: String) -> Data? {
        records[recipientDeviceId]
    }

    public func deleteLatest(recipientDeviceId: String) {
        records.removeValue(forKey: recipientDeviceId)
        versions[recipientDeviceId, default: 0] += 1
    }

    public func fetchChanges(
        recipientDeviceId: String,
        since changeToken: Data?
    ) -> MailboxChangeBatch {
        let current = versions[recipientDeviceId, default: 0]
        let previous = changeToken.flatMap(Self.decodeVersion) ?? 0
        return MailboxChangeBatch(
            latestData: current > previous ? records[recipientDeviceId] : nil,
            changeToken: Self.encodeVersion(current)
        )
    }

    private static func encodeVersion(_ value: UInt64) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private static func decodeVersion(_ data: Data) -> UInt64? {
        guard data.count == MemoryLayout<UInt64>.size else { return nil }
        return data.withUnsafeBytes { bytes in
            UInt64(bigEndian: bytes.loadUnaligned(as: UInt64.self))
        }
    }
}
