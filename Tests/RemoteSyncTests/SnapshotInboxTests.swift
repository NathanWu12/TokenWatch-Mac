import Foundation
import RemoteSync
import SyncSecurity
import TestSupport
import Testing

@Suite("Remote snapshot inbox")
struct SnapshotInboxTests {
    @Test("rejects duplicate, out-of-order and expired delivery")
    func deliverySemantics() async throws {
        let inbox = SnapshotInbox()
        let deviceId = "phone"
        let key = Data(repeating: 9, count: 32)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try SnapshotCrypto.seal(
            SampleSnapshots.p0(now: now),
            recipientDeviceId: deviceId,
            sharedKeyData: key,
            now: now
        )
        let newer = try SnapshotCrypto.seal(
            SampleSnapshots.p0(now: now.addingTimeInterval(10)),
            recipientDeviceId: deviceId,
            sharedKeyData: key,
            now: now.addingTimeInterval(10)
        )
        let old = try SnapshotCrypto.seal(
            SampleSnapshots.p0(now: now.addingTimeInterval(5)),
            recipientDeviceId: deviceId,
            sharedKeyData: key,
            now: now.addingTimeInterval(5)
        )
        let expired = try SnapshotCrypto.seal(
            SampleSnapshots.p0(now: now),
            recipientDeviceId: deviceId,
            sharedKeyData: key,
            now: now,
            ttl: 1
        )

        #expect(try await inbox.consume(
            first,
            recipientDeviceId: deviceId,
            sharedKeyData: key,
            now: now
        ) != .duplicate)
        #expect(try await inbox.consume(
            first,
            recipientDeviceId: deviceId,
            sharedKeyData: key,
            now: now
        ) == .duplicate)
        let restoredInbox = SnapshotInbox(state: await inbox.persistedState())
        #expect(try await restoredInbox.consume(
            first,
            recipientDeviceId: deviceId,
            sharedKeyData: key,
            now: now
        ) == .duplicate)
        _ = try await inbox.consume(
            newer,
            recipientDeviceId: deviceId,
            sharedKeyData: key,
            now: now.addingTimeInterval(10)
        )
        #expect(try await inbox.consume(
            old,
            recipientDeviceId: deviceId,
            sharedKeyData: key,
            now: now.addingTimeInterval(10)
        ) == .outOfOrder)
        #expect(try await inbox.consume(
            expired,
            recipientDeviceId: deviceId,
            sharedKeyData: key,
            now: now.addingTimeInterval(2)
        ) == .expired)
    }

    @Test("fake mailbox uses latest-state overwrite semantics")
    func fakeMailbox() async throws {
        let mailbox = InMemorySnapshotMailbox()
        await mailbox.saveLatest(Data("first".utf8), recipientDeviceId: "phone")
        await mailbox.saveLatest(Data("second".utf8), recipientDeviceId: "phone")
        #expect(await mailbox.fetchLatest(recipientDeviceId: "phone") == Data("second".utf8))
        #expect(await mailbox.fetchLatest(recipientDeviceId: "other") == nil)
        let firstChanges = await mailbox.fetchChanges(
            recipientDeviceId: "phone",
            since: nil
        )
        #expect(firstChanges.latestData == Data("second".utf8))
        let noChanges = await mailbox.fetchChanges(
            recipientDeviceId: "phone",
            since: firstChanges.changeToken
        )
        #expect(noChanges.latestData == nil)
        await mailbox.deleteLatest(recipientDeviceId: "phone")
        #expect(await mailbox.fetchLatest(recipientDeviceId: "phone") == nil)
    }

    @Test("encrypted Mac to mailbox to phone pipeline preserves the snapshot")
    func encryptedPipeline() async throws {
        let mac = DeviceIdentity.generate(deviceId: "mac")
        let phone = DeviceIdentity.generate(deviceId: "phone")
        let macKey = try mac.sharedKey(peerPublicKey: phone.publicKey)
        let phoneKey = try phone.sharedKey(peerPublicKey: mac.publicKey)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let original = SampleSnapshots.p0(now: now)
        let envelope = try SnapshotCrypto.seal(
            original,
            recipientDeviceId: phone.deviceId,
            sharedKeyData: macKey,
            now: now
        )
        let encoded = try SnapshotCrypto.encoder().encode(envelope)
        let mailbox = InMemorySnapshotMailbox()
        await mailbox.saveLatest(encoded, recipientDeviceId: phone.deviceId)

        let changes = await mailbox.fetchChanges(
            recipientDeviceId: phone.deviceId,
            since: nil
        )
        let payload = try #require(changes.latestData)
        let receivedEnvelope = try SnapshotCrypto.decoder().decode(
            EncryptedSnapshotEnvelope.self,
            from: payload
        )
        let decision = try await SnapshotInbox().consume(
            receivedEnvelope,
            recipientDeviceId: phone.deviceId,
            sharedKeyData: phoneKey,
            now: now
        )
        #expect(decision == .accepted(original))
    }
}
