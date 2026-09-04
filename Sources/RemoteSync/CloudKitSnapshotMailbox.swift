#if canImport(CloudKit)
@preconcurrency import CloudKit
import Foundation

public actor CloudKitSnapshotMailbox: ChangeTrackingSnapshotMailbox {
    public enum MailboxError: Error {
        case missingPayload
    }

    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private var prepared = false
    private var recordCache: [String: CKRecord] = [:]

    public init(
        containerIdentifier: String? = nil,
        zoneName: String = "TokenWatchMailbox"
    ) {
        let container = containerIdentifier.map(CKContainer.init(identifier:)) ?? CKContainer.default()
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    public func saveLatest(_ data: Data, recipientDeviceId: String) async throws {
        try await prepareIfNeeded()
        let recordID = CKRecord.ID(recordName: recordName(recipientDeviceId), zoneID: zoneID)
        let record = try await cachedOrFetchedRecord(
            recipientDeviceId: recipientDeviceId,
            recordID: recordID
        )
        applyLatestPayload(data, recipientDeviceId: recipientDeviceId, to: record)
        do {
            recordCache[recipientDeviceId] = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Another TokenWatch client may have updated the same latest-state record.
            // Refresh only on conflict instead of paying a read before every normal save.
            let fresh = try await database.record(for: recordID)
            applyLatestPayload(data, recipientDeviceId: recipientDeviceId, to: fresh)
            recordCache[recipientDeviceId] = try await database.save(fresh)
        } catch let error as CKError where error.code == .unknownItem {
            // A record cached earlier may have been removed elsewhere. Recreate the
            // latest-state slot instead of retrying the stale cached record forever.
            let fresh = CKRecord(recordType: "Snapshot", recordID: recordID)
            applyLatestPayload(data, recipientDeviceId: recipientDeviceId, to: fresh)
            recordCache[recipientDeviceId] = try await database.save(fresh)
        }
    }

    private func cachedOrFetchedRecord(
        recipientDeviceId: String,
        recordID: CKRecord.ID
    ) async throws -> CKRecord {
        if let cached = recordCache[recipientDeviceId] { return cached }
        do {
            let record = try await database.record(for: recordID)
            recordCache[recipientDeviceId] = record
            return record
        } catch let error as CKError where error.code == .unknownItem {
            let record = CKRecord(recordType: "Snapshot", recordID: recordID)
            recordCache[recipientDeviceId] = record
            return record
        }
    }

    private func applyLatestPayload(
        _ data: Data,
        recipientDeviceId: String,
        to record: CKRecord
    ) {
        record["recipientDeviceId"] = recipientDeviceId as CKRecordValue
        record["payload"] = data as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
    }

    public func fetchLatest(recipientDeviceId: String) async throws -> Data? {
        try await prepareIfNeeded()
        let recordID = CKRecord.ID(recordName: recordName(recipientDeviceId), zoneID: zoneID)
        do {
            let record = try await database.record(for: recordID)
            recordCache[recipientDeviceId] = record
            guard let payload = record["payload"] as? Data else {
                throw MailboxError.missingPayload
            }
            return payload
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    public func deleteLatest(recipientDeviceId: String) async throws {
        try await prepareIfNeeded()
        recordCache.removeValue(forKey: recipientDeviceId)
        let recordID = CKRecord.ID(
            recordName: recordName(recipientDeviceId),
            zoneID: zoneID
        )
        do {
            _ = try await database.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }

    public func installChangeSubscription() async throws {
        try await prepareIfNeeded()
        let subscriptionID = "TokenWatchMailboxChanges"
        do {
            _ = try await database.subscription(for: subscriptionID)
            return
        } catch let error as CKError {
            guard error.code == .unknownItem else { throw error }
        } catch {
            throw error
        }
        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID,
            subscriptionID: subscriptionID
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.save(subscription)
    }

    public func fetchChanges(
        recipientDeviceId: String,
        since changeToken: Data?
    ) async throws -> MailboxChangeBatch {
        try await prepareIfNeeded()
        var token = try changeToken.map(decodeChangeToken)
        var latestData: Data?
        var moreComing = true
        let expectedRecordID = CKRecord.ID(
            recordName: recordName(recipientDeviceId),
            zoneID: zoneID
        )

        while moreComing {
            let changes = try await database.recordZoneChanges(
                inZoneWith: zoneID,
                since: token,
                desiredKeys: ["payload", "recipientDeviceId", "updatedAt"]
            )
            if let result = changes.modificationResultsByID[expectedRecordID],
               case let .success(modification) = result {
                guard let payload = modification.record["payload"] as? Data else {
                    throw MailboxError.missingPayload
                }
                latestData = payload
            }
            token = changes.changeToken
            moreComing = changes.moreComing
        }

        guard let token else {
            throw MailboxError.missingPayload
        }
        return MailboxChangeBatch(
            latestData: latestData,
            changeToken: try encodeChangeToken(token)
        )
    }

    private func prepareIfNeeded() async throws {
        guard !prepared else { return }
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            _ = try await database.save(zone)
        } catch let error as CKError where error.code == .serverRejectedRequest
            || error.code == .zoneNotFound {
            throw error
        } catch let error as CKError where error.code == .partialFailure {
            throw error
        } catch {
            // Saving an existing zone can report an idempotent conflict. A record operation
            // below remains the authoritative availability check.
        }
        prepared = true
    }

    private func recordName(_ deviceId: String) -> String {
        let safe = deviceId
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "latest-\(safe)"
    }

    private func encodeChangeToken(_ token: CKServerChangeToken) throws -> Data {
        try NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
        )
    }

    private func decodeChangeToken(_ data: Data) throws -> CKServerChangeToken {
        guard let token = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: CKServerChangeToken.self,
            from: data
        ) else {
            throw MailboxError.missingPayload
        }
        return token
    }
}
#endif
