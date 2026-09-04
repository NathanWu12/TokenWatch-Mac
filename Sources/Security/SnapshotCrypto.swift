import CryptoKit
import Domain
import Foundation

public struct DeviceIdentity: Codable, Equatable, Sendable {
    public let deviceId: String
    public let privateKey: Data
    public let publicKey: Data

    public init(deviceId: String, privateKey: Data, publicKey: Data) {
        self.deviceId = deviceId
        self.privateKey = privateKey
        self.publicKey = publicKey
    }

    public static func generate(deviceId: String = UUID().uuidString.lowercased()) -> Self {
        let key = Curve25519.KeyAgreement.PrivateKey()
        return Self(
            deviceId: deviceId,
            privateKey: key.rawRepresentation,
            publicKey: key.publicKey.rawRepresentation
        )
    }

    public func sharedKey(peerPublicKey: Data) throws -> Data {
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        let salt = Data("TokenWatch.P0.snapshot.v1".utf8)
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data(),
            outputByteCount: 32
        ).withUnsafeBytes { Data($0) }
    }
}

public struct PairingChallenge: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let macDeviceId: String
    public let macPublicKey: Data
    public let nonce: Data
    public let expiresAt: Date

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        macDeviceId: String,
        macPublicKey: Data,
        nonce: Data,
        expiresAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.macDeviceId = macDeviceId
        self.macPublicKey = macPublicKey
        self.nonce = nonce
        self.expiresAt = expiresAt
    }
}

public struct PairingInvitation: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let deviceId: String
    public let publicKey: Data
    public let challengeNonce: Data
    public let macDeviceId: String
    public let macPublicKey: Data
    public let proof: Data

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        deviceId: String,
        publicKey: Data,
        challengeNonce: Data,
        macDeviceId: String,
        macPublicKey: Data,
        proof: Data
    ) {
        self.schemaVersion = schemaVersion
        self.deviceId = deviceId
        self.publicKey = publicKey
        self.challengeNonce = challengeNonce
        self.macDeviceId = macDeviceId
        self.macPublicKey = macPublicKey
        self.proof = proof
    }
}

public struct SnapshotWireMessage: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let senderDeviceId: String
    public let senderPublicKey: Data
    public let pairingProof: Data
    public let envelope: EncryptedSnapshotEnvelope

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        senderDeviceId: String,
        senderPublicKey: Data,
        pairingProof: Data,
        envelope: EncryptedSnapshotEnvelope
    ) {
        self.schemaVersion = schemaVersion
        self.senderDeviceId = senderDeviceId
        self.senderPublicKey = senderPublicKey
        self.pairingProof = pairingProof
        self.envelope = envelope
    }
}

public enum PairingProof {
    public static func invitation(
        pairingCode: String,
        deviceId: String,
        publicKey: Data,
        challengeNonce: Data,
        macDeviceId: String,
        macPublicKey: Data
    ) -> Data {
        authenticate(
            pairingCode: pairingCode,
            label: "phone-invitation",
            values: [
                Data(deviceId.utf8),
                publicKey,
                challengeNonce,
                Data(macDeviceId.utf8),
                macPublicKey,
            ]
        )
    }

    public static func acceptance(
        pairingCode: String,
        phoneDeviceId: String,
        phonePublicKey: Data,
        macDeviceId: String,
        macPublicKey: Data
    ) -> Data {
        authenticate(
            pairingCode: pairingCode,
            label: "mac-acceptance",
            values: [
                Data(phoneDeviceId.utf8),
                phonePublicKey,
                Data(macDeviceId.utf8),
                macPublicKey,
            ]
        )
    }

    public static func isValidInvitation(
        _ proof: Data,
        pairingCode: String,
        deviceId: String,
        publicKey: Data,
        challengeNonce: Data,
        macDeviceId: String,
        macPublicKey: Data
    ) -> Bool {
        safeCompare(
            proof,
            invitation(
                pairingCode: pairingCode,
                deviceId: deviceId,
                publicKey: publicKey,
                challengeNonce: challengeNonce,
                macDeviceId: macDeviceId,
                macPublicKey: macPublicKey
            )
        )
    }

    public static func isValidAcceptance(
        _ proof: Data,
        pairingCode: String,
        phoneDeviceId: String,
        phonePublicKey: Data,
        macDeviceId: String,
        macPublicKey: Data
    ) -> Bool {
        safeCompare(
            proof,
            acceptance(
                pairingCode: pairingCode,
                phoneDeviceId: phoneDeviceId,
                phonePublicKey: phonePublicKey,
                macDeviceId: macDeviceId,
                macPublicKey: macPublicKey
            )
        )
    }

    private static func authenticate(
        pairingCode: String,
        label: String,
        values: [Data]
    ) -> Data {
        var material = Data(label.utf8)
        material.append(0)
        for value in values {
            material.append(value)
            material.append(0)
        }
        return Data(HMAC<SHA256>.authenticationCode(
            for: material,
            using: SymmetricKey(data: Data(pairingCode.utf8))
        ))
    }

    private static func safeCompare(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { result, pair in
            result | (pair.0 ^ pair.1)
        } == 0
    }
}

public enum PairingValidator {
    public static func isValid(
        invitation: PairingInvitation,
        challenge: PairingChallenge,
        pairingCode: String,
        now: Date
    ) -> Bool {
        invitation.schemaVersion == PairingInvitation.currentSchemaVersion
            && challenge.schemaVersion == PairingChallenge.currentSchemaVersion
            && invitation.deviceId.count <= 128
            && invitation.publicKey.count == 32
            && challenge.macDeviceId.count <= 128
            && challenge.macPublicKey.count == 32
            && challenge.nonce.count == 32
            && now < challenge.expiresAt
            && invitation.challengeNonce == challenge.nonce
            && invitation.macDeviceId == challenge.macDeviceId
            && invitation.macPublicKey == challenge.macPublicKey
            && PairingProof.isValidInvitation(
                invitation.proof,
                pairingCode: pairingCode,
                deviceId: invitation.deviceId,
                publicKey: invitation.publicKey,
                challengeNonce: challenge.nonce,
                macDeviceId: challenge.macDeviceId,
                macPublicKey: challenge.macPublicKey
            )
    }
}

public enum DeviceFingerprint {
    public static func display(publicKey: Data) -> String {
        SHA256.hash(data: publicKey)
            .prefix(6)
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")
    }
}

public struct EncryptedSnapshotEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let messageId: UUID
    public let deviceId: String
    public let createdAt: Date
    public let expiresAt: Date
    public let correlationId: UUID
    public let nonce: Data
    public let ciphertext: Data
    public let authenticationTag: Data
    public let signature: Data

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        messageId: UUID,
        deviceId: String,
        createdAt: Date,
        expiresAt: Date,
        correlationId: UUID,
        nonce: Data,
        ciphertext: Data,
        authenticationTag: Data,
        signature: Data
    ) {
        self.schemaVersion = schemaVersion
        self.messageId = messageId
        self.deviceId = deviceId
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.correlationId = correlationId
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.authenticationTag = authenticationTag
        self.signature = signature
    }

    public func isExpired(at now: Date) -> Bool {
        now >= expiresAt
    }
}

public enum SnapshotCrypto {
    public enum CryptoError: Error, Equatable {
        case invalidKey
        case invalidSignature
        case expired
        case wrongRecipient
        case incompatibleSchema
    }

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

    public static func seal(
        _ snapshot: UsageSnapshot,
        recipientDeviceId: String,
        sharedKeyData: Data,
        now: Date = Date(),
        ttl: TimeInterval = 24 * 60 * 60,
        messageId: UUID = UUID(),
        correlationId: UUID = UUID()
    ) throws -> EncryptedSnapshotEnvelope {
        let key = try symmetricKey(sharedKeyData)
        let plaintext = try encoder().encode(snapshot)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        // JSONEncoder's ISO-8601 strategy serializes whole seconds. Normalize
        // before signing so the authenticated timestamps survive wire encoding.
        let createdAt = wireDate(now)
        let expiresAt = wireDate(now.addingTimeInterval(ttl))
        let unsigned = EncryptedSnapshotEnvelope(
            messageId: messageId,
            deviceId: recipientDeviceId,
            createdAt: createdAt,
            expiresAt: expiresAt,
            correlationId: correlationId,
            nonce: Data(sealed.nonce),
            ciphertext: sealed.ciphertext,
            authenticationTag: sealed.tag,
            signature: Data()
        )
        let signature = Data(HMAC<SHA256>.authenticationCode(
            for: signingMaterial(unsigned),
            using: key
        ))
        return EncryptedSnapshotEnvelope(
            messageId: unsigned.messageId,
            deviceId: unsigned.deviceId,
            createdAt: unsigned.createdAt,
            expiresAt: unsigned.expiresAt,
            correlationId: unsigned.correlationId,
            nonce: unsigned.nonce,
            ciphertext: unsigned.ciphertext,
            authenticationTag: unsigned.authenticationTag,
            signature: signature
        )
    }

    public static func open(
        _ envelope: EncryptedSnapshotEnvelope,
        recipientDeviceId: String,
        sharedKeyData: Data,
        now: Date = Date()
    ) throws -> UsageSnapshot {
        guard envelope.schemaVersion == EncryptedSnapshotEnvelope.currentSchemaVersion else {
            throw CryptoError.incompatibleSchema
        }
        guard envelope.deviceId == recipientDeviceId else {
            throw CryptoError.wrongRecipient
        }
        guard !envelope.isExpired(at: now) else {
            throw CryptoError.expired
        }
        let key = try symmetricKey(sharedKeyData)
        guard HMAC<SHA256>.isValidAuthenticationCode(
            envelope.signature,
            authenticating: signingMaterial(envelope),
            using: key
        ) else {
            throw CryptoError.invalidSignature
        }
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: envelope.nonce),
            ciphertext: envelope.ciphertext,
            tag: envelope.authenticationTag
        )
        let plaintext = try AES.GCM.open(box, using: key)
        let snapshot = try decoder().decode(UsageSnapshot.self, from: plaintext)
        guard snapshot.schemaVersion == UsageSnapshot.currentSchemaVersion else {
            throw CryptoError.incompatibleSchema
        }
        return snapshot
    }

    private static func symmetricKey(_ data: Data) throws -> SymmetricKey {
        guard data.count == 32 else { throw CryptoError.invalidKey }
        return SymmetricKey(data: data)
    }

    private static func wireDate(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }

    private static func signingMaterial(_ envelope: EncryptedSnapshotEnvelope) -> Data {
        var result = Data()
        func append(_ value: String) {
            result.append(Data(value.utf8))
            result.append(0)
        }
        append(String(envelope.schemaVersion))
        append(envelope.messageId.uuidString.lowercased())
        append(envelope.deviceId)
        append(String(Int64(envelope.createdAt.timeIntervalSince1970 * 1_000)))
        append(String(Int64(envelope.expiresAt.timeIntervalSince1970 * 1_000)))
        append(envelope.correlationId.uuidString.lowercased())
        result.append(envelope.nonce)
        result.append(envelope.ciphertext)
        result.append(envelope.authenticationTag)
        return result
    }
}
