import CryptoKit
import Domain
import Foundation

public struct SnapshotEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let messageId: UUID
    public let deviceId: String
    public let createdAt: Date
    public let expiresAt: Date
    public let correlationId: UUID
    public let payload: UsageSnapshot
    public let signature: Data?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        messageId: UUID = UUID(),
        deviceId: String,
        createdAt: Date,
        expiresAt: Date,
        correlationId: UUID = UUID(),
        payload: UsageSnapshot,
        signature: Data? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.messageId = messageId
        self.deviceId = deviceId
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.correlationId = correlationId
        self.payload = payload
        self.signature = signature
    }

    public func isExpired(at now: Date) -> Bool {
        now >= expiresAt
    }
}

public enum SnapshotCodec {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode(_ snapshot: UsageSnapshot) throws -> Data {
        try encoder().encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> UsageSnapshot {
        try decoder().decode(UsageSnapshot.self, from: data)
    }
}
