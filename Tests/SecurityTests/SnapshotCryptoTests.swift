import Domain
import Foundation
import SyncSecurity
import TestSupport
import Testing

@Suite("Snapshot crypto")
struct SnapshotCryptoTests {
    @Test("device key agreement is symmetric and snapshots round trip")
    func roundTrip() throws {
        let mac = DeviceIdentity.generate(deviceId: "mac")
        let phone = DeviceIdentity.generate(deviceId: "phone")
        let macKey = try mac.sharedKey(peerPublicKey: phone.publicKey)
        let phoneKey = try phone.sharedKey(peerPublicKey: mac.publicKey)
        #expect(macKey == phoneKey)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = SampleSnapshots.p0(now: now)
        let envelope = try SnapshotCrypto.seal(
            snapshot,
            recipientDeviceId: phone.deviceId,
            sharedKeyData: macKey,
            now: now
        )
        let opened = try SnapshotCrypto.open(
            envelope,
            recipientDeviceId: phone.deviceId,
            sharedKeyData: phoneKey,
            now: now
        )
        #expect(opened == snapshot)
    }

    @Test("wire encoding preserves signatures when the source clock has subsecond precision")
    func wireRoundTripWithSubsecondClock() throws {
        let key = Data(repeating: 11, count: 32)
        let recipient = "phone"
        let snapshotTime = Date(timeIntervalSince1970: 1_700_000_000)
        let wireNow = Date(timeIntervalSince1970: 1_700_000_000.987)
        let snapshot = SampleSnapshots.p0(now: snapshotTime)
        let envelope = try SnapshotCrypto.seal(
            snapshot,
            recipientDeviceId: recipient,
            sharedKeyData: key,
            now: wireNow
        )

        let encoded = try SnapshotCrypto.encoder().encode(envelope)
        let decoded = try SnapshotCrypto.decoder().decode(
            EncryptedSnapshotEnvelope.self,
            from: encoded
        )
        let opened = try SnapshotCrypto.open(
            decoded,
            recipientDeviceId: recipient,
            sharedKeyData: key,
            now: wireNow
        )

        #expect(decoded.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(opened == snapshot)
    }

    @Test("rejects tampering, wrong recipient and expiry")
    func rejectsInvalidMessages() throws {
        let identity = DeviceIdentity.generate(deviceId: "phone")
        let key = Data(repeating: 7, count: 32)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let envelope = try SnapshotCrypto.seal(
            SampleSnapshots.p0(now: now),
            recipientDeviceId: identity.deviceId,
            sharedKeyData: key,
            now: now,
            ttl: 60
        )
        #expect(throws: SnapshotCrypto.CryptoError.wrongRecipient) {
            try SnapshotCrypto.open(
                envelope,
                recipientDeviceId: "another-phone",
                sharedKeyData: key,
                now: now
            )
        }
        #expect(throws: SnapshotCrypto.CryptoError.expired) {
            try SnapshotCrypto.open(
                envelope,
                recipientDeviceId: identity.deviceId,
                sharedKeyData: key,
                now: now.addingTimeInterval(60)
            )
        }
        let tampered = EncryptedSnapshotEnvelope(
            messageId: envelope.messageId,
            deviceId: envelope.deviceId,
            createdAt: envelope.createdAt,
            expiresAt: envelope.expiresAt,
            correlationId: envelope.correlationId,
            nonce: envelope.nonce,
            ciphertext: envelope.ciphertext + Data([0]),
            authenticationTag: envelope.authenticationTag,
            signature: envelope.signature
        )
        #expect(throws: SnapshotCrypto.CryptoError.invalidSignature) {
            try SnapshotCrypto.open(
                tampered,
                recipientDeviceId: identity.deviceId,
                sharedKeyData: key,
                now: now
            )
        }
    }

    @Test("pairing proof authenticates both sides without transmitting the code")
    func pairingProof() {
        let code = "123456"
        let phone = DeviceIdentity.generate(deviceId: "phone")
        let mac = DeviceIdentity.generate(deviceId: "mac")
        let challengeNonce = Data(repeating: 7, count: 32)
        let invitation = PairingProof.invitation(
            pairingCode: code,
            deviceId: phone.deviceId,
            publicKey: phone.publicKey,
            challengeNonce: challengeNonce,
            macDeviceId: mac.deviceId,
            macPublicKey: mac.publicKey
        )
        #expect(PairingProof.isValidInvitation(
            invitation,
            pairingCode: code,
            deviceId: phone.deviceId,
            publicKey: phone.publicKey,
            challengeNonce: challengeNonce,
            macDeviceId: mac.deviceId,
            macPublicKey: mac.publicKey
        ))
        #expect(!PairingProof.isValidInvitation(
            invitation,
            pairingCode: "654321",
            deviceId: phone.deviceId,
            publicKey: phone.publicKey,
            challengeNonce: challengeNonce,
            macDeviceId: mac.deviceId,
            macPublicKey: mac.publicKey
        ))
        #expect(!PairingProof.isValidInvitation(
            invitation,
            pairingCode: code,
            deviceId: phone.deviceId,
            publicKey: phone.publicKey,
            challengeNonce: Data(repeating: 8, count: 32),
            macDeviceId: mac.deviceId,
            macPublicKey: mac.publicKey
        ))

        let acceptance = PairingProof.acceptance(
            pairingCode: code,
            phoneDeviceId: phone.deviceId,
            phonePublicKey: phone.publicKey,
            macDeviceId: mac.deviceId,
            macPublicKey: mac.publicKey
        )
        #expect(PairingProof.isValidAcceptance(
            acceptance,
            pairingCode: code,
            phoneDeviceId: phone.deviceId,
            phonePublicKey: phone.publicKey,
            macDeviceId: mac.deviceId,
            macPublicKey: mac.publicKey
        ))
        #expect(!PairingProof.isValidAcceptance(
            acceptance,
            pairingCode: code,
            phoneDeviceId: phone.deviceId,
            phonePublicKey: phone.publicKey,
            macDeviceId: "impostor",
            macPublicKey: mac.publicKey
        ))
    }

    @Test("challenge validation rejects replay, expiry and wrong Mac identity")
    func challengeValidation() {
        let now = Date(timeIntervalSince1970: 1_000)
        let code = "123456"
        let phone = DeviceIdentity.generate(deviceId: "phone")
        let mac = DeviceIdentity.generate(deviceId: "mac")
        let nonce = Data(repeating: 9, count: 32)
        let challenge = PairingChallenge(
            macDeviceId: mac.deviceId,
            macPublicKey: mac.publicKey,
            nonce: nonce,
            expiresAt: now.addingTimeInterval(30)
        )
        let invitation = PairingInvitation(
            deviceId: phone.deviceId,
            publicKey: phone.publicKey,
            challengeNonce: nonce,
            macDeviceId: mac.deviceId,
            macPublicKey: mac.publicKey,
            proof: PairingProof.invitation(
                pairingCode: code,
                deviceId: phone.deviceId,
                publicKey: phone.publicKey,
                challengeNonce: nonce,
                macDeviceId: mac.deviceId,
                macPublicKey: mac.publicKey
            )
        )

        #expect(PairingValidator.isValid(
            invitation: invitation,
            challenge: challenge,
            pairingCode: code,
            now: now
        ))
        #expect(!PairingValidator.isValid(
            invitation: invitation,
            challenge: challenge,
            pairingCode: code,
            now: challenge.expiresAt
        ))

        let replayChallenge = PairingChallenge(
            macDeviceId: mac.deviceId,
            macPublicKey: mac.publicKey,
            nonce: Data(repeating: 8, count: 32),
            expiresAt: now.addingTimeInterval(30)
        )
        #expect(!PairingValidator.isValid(
            invitation: invitation,
            challenge: replayChallenge,
            pairingCode: code,
            now: now
        ))
    }

    @Test("device fingerprint is stable and human-comparable")
    func deviceFingerprint() {
        let key = Data(repeating: 0x42, count: 32)
        let first = DeviceFingerprint.display(publicKey: key)
        let second = DeviceFingerprint.display(publicKey: key)

        #expect(first == second)
        #expect(first.split(separator: ":").count == 6)
        #expect(first.count == 17)
    }
}
