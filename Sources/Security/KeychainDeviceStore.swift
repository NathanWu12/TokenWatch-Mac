import Foundation
import Security

public struct KeychainDeviceStore: Sendable {
    public enum StoreError: Error {
        case invalidStoredValue
        case readFailed(OSStatus)
        case writeFailed(OSStatus)
    }

    private let service: String

    public init(service: String) {
        self.service = service
    }

    public func loadOrCreateIdentity(account: String) throws -> DeviceIdentity {
        if let data = try loadData(account: account) {
            do {
                return try SnapshotCrypto.decoder().decode(DeviceIdentity.self, from: data)
            } catch {
                throw StoreError.invalidStoredValue
            }
        }
        let identity = DeviceIdentity.generate()
        try saveData(
            SnapshotCrypto.encoder().encode(identity),
            account: account
        )
        return identity
    }

    public func saveData(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StoreError.writeFailed(status)
        }
    }

    public func loadData(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw StoreError.readFailed(status)
        }
        guard let data = result as? Data else {
            throw StoreError.invalidStoredValue
        }
        return data
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
