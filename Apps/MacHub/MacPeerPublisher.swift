@preconcurrency import Network
import Domain
import Foundation
import LocalTransport
import Observation
import OSLog
import RemoteSync
import Security
import SyncSecurity

struct PairedPhone: Codable, Equatable, Sendable {
    let deviceId: String
    let displayName: String
    let publicKey: Data
}

@MainActor
@Observable
final class MacPeerPublisher {
    private static let serviceType = "_tokenwatch-p0._tcp"
    private static let logger = Logger(
        subsystem: "com.nathanwu.TokenWatch",
        category: "LocalSync"
    )

    private(set) var connectedPeers: [String] = []
    private(set) var pairingCode: String
    private(set) var stateText: String.LocalizationValue = "正在等待 iPhone"
    private(set) var remoteStatusText: String.LocalizationValue = "远程同步等待首次配对"

    @ObservationIgnored
    private var listener: NWListener?
    @ObservationIgnored
    private var sessions: [UUID: MacLocalSession] = [:]
    @ObservationIgnored
    private var rejectedPairingAttempts: [Date] = []
    @ObservationIgnored
    private let identity: DeviceIdentity?
    @ObservationIgnored
    private let mailbox: CloudKitSnapshotMailbox?
    @ObservationIgnored
    private let pairedStore = MacPairedPhoneStore()
    @ObservationIgnored
    private var pairedPhones: [String: PairedPhone] = [:]
    @ObservationIgnored
    private var latestSnapshot: UsageSnapshot?
    @ObservationIgnored
    private var pendingRemoteSnapshot: UsageSnapshot?
    @ObservationIgnored
    private var lastRemoteSnapshot: UsageSnapshot?
    @ObservationIgnored
    private var remotePublishTask: Task<Void, Never>?
    @ObservationIgnored
    private var remoteRetryAttempt = 0
    @ObservationIgnored
    var onAuthenticatedPeerConnected: (() -> Void)?

    var pairedDevices: [PairedPhone] {
        pairedPhones.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var publicKeyFingerprint: String {
        identity.map { DeviceFingerprint.display(publicKey: $0.publicKey) }
            ?? String(localized: "不可用")
    }

    init() {
        let initialPairingCode = try? PairingSecretStore.loadOrCreateCode()
        let keychain = KeychainDeviceStore(service: "com.nathanwu.TokenWatch.device")
        let loadedIdentity = try? keychain.loadOrCreateIdentity(account: "mac-hub-identity")
        identity = loadedIdentity
        mailbox = Self.hasCloudKitEntitlement()
            ? CloudKitSnapshotMailbox(
                containerIdentifier: "iCloud.com.nathanwu.TokenWatch"
            )
            : nil
        pairingCode = initialPairingCode ?? String(localized: "不可用")
        pairedPhones = (try? pairedStore.load())
            .map { Dictionary(uniqueKeysWithValues: $0.map { ($0.deviceId, $0) }) } ?? [:]

        if initialPairingCode == nil || loadedIdentity == nil {
            stateText = "Keychain 不可用，已停用新配对"
        } else {
            startListener()
            if !pairedPhones.isEmpty {
                remoteStatusText = "远程同步将在数据更新后写入 iCloud"
            }
        }
    }

    isolated deinit {
        remotePublishTask?.cancel()
        listener?.cancel()
        sessions.values.forEach { $0.cancel() }
    }

    func publish(_ snapshot: UsageSnapshot) {
        latestSnapshot = snapshot
        sendLatest()
        enqueueRemote(snapshot)
    }

    func rotatePairingCode() {
        guard let next = try? PairingSecretStore.rotateCode() else {
            stateText = "无法更新配对码"
            return
        }
        pairingCode = next
        sessions.values.forEach { $0.cancel() }
        sessions.removeAll()
        updateConnectedPeers()
        stateText = "配对码已更新"
    }

    func revoke(deviceId: String) {
        guard pairedPhones.removeValue(forKey: deviceId) != nil else { return }
        try? pairedStore.save(Array(pairedPhones.values))
        rotatePairingCode()
        stateText = "设备已撤销 · 其他设备需使用新配对码重连"
        guard let mailbox else { return }
        Task {
            try? await mailbox.deleteLatest(recipientDeviceId: deviceId)
        }
    }

    func revokeAllDevices() {
        let deviceIds = Array(pairedPhones.keys)
        guard !deviceIds.isEmpty else { return }
        pairedPhones.removeAll()
        try? pairedStore.save([])
        rotatePairingCode()
        stateText = "所有设备已撤销"
        guard let mailbox else { return }
        Task {
            for deviceId in deviceIds {
                try? await mailbox.deleteLatest(recipientDeviceId: deviceId)
            }
        }
    }

    private func startListener() {
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(
                name: "TokenWatch",
                type: Self.serviceType
            )
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection)
                }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            stateText = "无法启动本地同步：\(error.localizedDescription)"
            Self.logger.error("Unable to create Bonjour listener")
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            stateText = "正在等待 iPhone"
            Self.logger.info("Authenticated Bonjour listener is ready")
        case let .failed(error):
            stateText = "无法启动本地同步：\(error.localizedDescription)"
            Self.logger.error(
                "Bonjour listener failed: \(error.debugDescription, privacy: .public)"
            )
            listener?.cancel()
            listener = nil
        case .cancelled:
            break
        case .setup, .waiting:
            stateText = "正在等待本地网络"
        @unknown default:
            stateText = "连接状态未知"
        }
    }

    private func accept(_ connection: NWConnection) {
        guard let identity,
              let nonce = Self.secureRandomData(count: 32) else {
            connection.cancel()
            return
        }
        let id = UUID()
        let session = MacLocalSession(connection: connection)
        session.challenge = PairingChallenge(
            macDeviceId: identity.deviceId,
            macPublicKey: identity.publicKey,
            nonce: nonce,
            expiresAt: Date().addingTimeInterval(30)
        )
        sessions[id] = session
        session.onState = { [weak self, weak session] state in
            guard let self, self.sessions[id] === session else { return }
            switch state {
            case .ready:
                stateText = "正在验证配对"
                do {
                    guard let challenge = session?.challenge else {
                        session?.cancel()
                        return
                    }
                    try session?.send(SnapshotCrypto.encoder().encode(challenge))
                } catch {
                    session?.cancel()
                }
            case .failed, .cancelled:
                removeSession(id)
            case .setup, .preparing, .waiting:
                break
            @unknown default:
                removeSession(id)
            }
        }
        session.onFrame = { [weak self] data in
            self?.handlePairingFrame(data, sessionID: id)
        }
        session.start()
    }

    private func handlePairingFrame(_ data: Data, sessionID: UUID) {
        guard let session = sessions[sessionID],
              session.phone == nil,
              let challenge = session.challenge else {
            sessions[sessionID]?.cancel()
            return
        }
        guard canAttemptPairing() else {
            stateText = "配对尝试过多，请稍后再试"
            session.cancel()
            return
        }
        guard let invitation = try? SnapshotCrypto.decoder().decode(
            PairingInvitation.self,
            from: data
        ),
              PairingValidator.isValid(
                  invitation: invitation,
                  challenge: challenge,
                  pairingCode: pairingCode,
                  now: Date()
              ) else {
            recordRejectedPairing()
            stateText = "已拒绝无效配对请求"
            Self.logger.notice("Rejected invalid local pairing request")
            session.cancel()
            return
        }

        let existingName = pairedPhones[invitation.deviceId]?.displayName
        let phone = PairedPhone(
            deviceId: invitation.deviceId,
            displayName: existingName ?? "iPhone · \(invitation.deviceId.prefix(8))",
            publicKey: invitation.publicKey
        )
        session.phone = phone
        pairedPhones[phone.deviceId] = phone
        try? pairedStore.save(Array(pairedPhones.values))
        updateConnectedPeers()
        stateText = "iPhone 已连接"
        Self.logger.info("Authenticated iPhone connection established")
        sendLatest(to: session)
        onAuthenticatedPeerConnected?()
        if let latestSnapshot {
            enqueueRemote(latestSnapshot, force: true)
        }
    }

    private func canAttemptPairing(now: Date = Date()) -> Bool {
        rejectedPairingAttempts.removeAll {
            now.timeIntervalSince($0) > 60
        }
        return rejectedPairingAttempts.count < 10
    }

    private func recordRejectedPairing() {
        rejectedPairingAttempts.append(Date())
    }

    private func removeSession(_ id: UUID) {
        sessions.removeValue(forKey: id)
        updateConnectedPeers()
        if connectedPeers.isEmpty {
            stateText = "正在等待 iPhone"
        }
    }

    private func updateConnectedPeers() {
        connectedPeers = sessions.values.compactMap(\.phone?.displayName)
    }

    private func sendLatest() {
        guard latestSnapshot != nil else { return }
        var successful = 0
        for session in sessions.values where session.phone != nil {
            if sendLatest(to: session) {
                successful += 1
            }
        }
        if successful > 0 {
            stateText = "已同步到 \(successful) 台 iPhone"
        }
    }

    @discardableResult
    private func sendLatest(to session: MacLocalSession) -> Bool {
        guard let latestSnapshot,
              let identity,
              let phone = session.phone else {
            return false
        }
        do {
            let data = try makeWireData(
                snapshot: latestSnapshot,
                identity: identity,
                phone: phone
            )
            try session.send(data)
            return true
        } catch {
            Self.logger.error("Unable to send encrypted local snapshot")
            session.cancel()
            return false
        }
    }

    private func enqueueRemote(_ snapshot: UsageSnapshot, force: Bool = false) {
        if !force {
            if let pendingRemoteSnapshot,
               pendingRemoteSnapshot.hasSameContent(as: snapshot) {
                return
            }
            if remotePublishTask == nil,
               let lastRemoteSnapshot,
               lastRemoteSnapshot.hasSameContent(as: snapshot) {
                return
            }
        }

        pendingRemoteSnapshot = snapshot
        guard remotePublishTask == nil else { return }
        remotePublishTask = Task { [weak self] in
            await self?.drainRemoteSnapshots()
        }
    }

    private func drainRemoteSnapshots() async {
        defer { remotePublishTask = nil }
        while !Task.isCancelled, let next = pendingRemoteSnapshot {
            pendingRemoteSnapshot = nil
            switch await publishRemoteNow(next) {
            case .success:
                lastRemoteSnapshot = next
                remoteRetryAttempt = 0
            case .unavailable:
                remoteRetryAttempt = 0
            case .retryableFailure:
                // Keep only the newest state while backing off. A newer publish that
                // arrives during sleep overwrites this pending retry.
                if pendingRemoteSnapshot == nil {
                    pendingRemoteSnapshot = next
                }
                remoteRetryAttempt += 1
                let delay = RetrySchedule.delay(
                    attempt: remoteRetryAttempt - 1,
                    baseDelay: 15,
                    maximumDelay: 15 * 60,
                    jitterFraction: 0.2,
                    jitterUnit: Double.random(in: 0...1)
                )
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
            }
        }
    }

    private func publishRemoteNow(_ snapshot: UsageSnapshot) async -> RemotePublishResult {
        guard let identity else {
            remoteStatusText = "远程同步不可用：设备密钥缺失"
            return .unavailable
        }
        guard let mailbox else {
            remoteStatusText = "iCloud entitlement 未启用 · 局域网同步可用"
            return .unavailable
        }
        let phones = Array(pairedPhones.values)
        guard !phones.isEmpty else {
            remoteStatusText = "远程同步等待首次配对"
            return .unavailable
        }

        remoteStatusText = "正在更新远程加密快照"
        var successes = 0
        for phone in phones {
            guard !Task.isCancelled else { return .unavailable }
            do {
                let data = try makeEnvelopeData(
                    snapshot: snapshot,
                    identity: identity,
                    phone: phone
                )
                try await mailbox.saveLatest(data, recipientDeviceId: phone.deviceId)
                successes += 1
            } catch {
                Self.logger.error("Unable to update encrypted CloudKit snapshot")
                remoteStatusText = "iCloud 暂不可用 · 局域网同步不受影响"
            }
        }
        if successes == phones.count {
            remoteStatusText = "远程加密快照已更新"
            return .success
        }
        return .retryableFailure
    }

    private static func hasCloudKitEntitlement() -> Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess,
              let code else {
            return false
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return false
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String]
                as? [String: Any],
              let services = entitlements["com.apple.developer.icloud-services"]
                as? [String] else {
            return false
        }
        return services.contains("CloudKit")
    }

    private static func secureRandomData(count: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            return nil
        }
        return Data(bytes)
    }

    private func makeWireData(
        snapshot: UsageSnapshot,
        identity: DeviceIdentity,
        phone: PairedPhone
    ) throws -> Data {
        let envelope = try makeEnvelope(snapshot: snapshot, identity: identity, phone: phone)
        return try SnapshotCrypto.encoder().encode(
            SnapshotWireMessage(
                senderDeviceId: identity.deviceId,
                senderPublicKey: identity.publicKey,
                pairingProof: PairingProof.acceptance(
                    pairingCode: pairingCode,
                    phoneDeviceId: phone.deviceId,
                    phonePublicKey: phone.publicKey,
                    macDeviceId: identity.deviceId,
                    macPublicKey: identity.publicKey
                ),
                envelope: envelope
            )
        )
    }

    private func makeEnvelopeData(
        snapshot: UsageSnapshot,
        identity: DeviceIdentity,
        phone: PairedPhone
    ) throws -> Data {
        try SnapshotCrypto.encoder().encode(
            makeEnvelope(snapshot: snapshot, identity: identity, phone: phone)
        )
    }

    private func makeEnvelope(
        snapshot: UsageSnapshot,
        identity: DeviceIdentity,
        phone: PairedPhone
    ) throws -> EncryptedSnapshotEnvelope {
        let key = try identity.sharedKey(peerPublicKey: phone.publicKey)
        return try SnapshotCrypto.seal(
            snapshot,
            recipientDeviceId: phone.deviceId,
            sharedKeyData: key,
            ttl: 24 * 60 * 60
        )
    }
}

@MainActor
private final class MacLocalSession {
    var onState: ((NWConnection.State) -> Void)?
    var onFrame: ((Data) -> Void)?
    var phone: PairedPhone?
    var challenge: PairingChallenge?

    private let connection: NWConnection
    private var decoder = LocalFrameDecoder()
    private var isCancelled = false

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.onState?(state)
            }
        }
        connection.start(queue: .main)
        receive()
    }

    func send(_ payload: Data) throws {
        let frame = try LocalFrameEncoder.encode(payload)
        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in
                self?.cancel()
            }
        })
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        connection.cancel()
    }

    private func receive() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, !self.isCancelled else { return }
                do {
                    if let data, !data.isEmpty {
                        for frame in try self.decoder.append(data) {
                            self.onFrame?(frame)
                        }
                    }
                } catch {
                    self.cancel()
                    return
                }
                if isComplete || error != nil {
                    self.cancel()
                } else {
                    self.receive()
                }
            }
        }
    }
}

private enum RemotePublishResult {
    case success
    case retryableFailure
    case unavailable
}

private struct MacPairedPhoneStore: Sendable {
    func save(_ phones: [PairedPhone]) throws {
        let data = try SnapshotCrypto.encoder().encode(phones)
        let url = try fileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    func load() throws -> [PairedPhone] {
        try SnapshotCrypto.decoder().decode(
            [PairedPhone].self,
            from: Data(contentsOf: try fileURL())
        )
    }

    private func fileURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appending(path: "TokenWatch", directoryHint: .isDirectory)
            .appending(path: "paired-phones.json")
    }
}

private enum PairingSecretStore {
    private static let service = "com.nathanwu.TokenWatch.pairing"
    private static let account = "local-pairing-code"

    static func loadOrCreateCode() throws -> String {
        if let existing = try load() { return existing }
        return try rotateCode()
    }

    static func rotateCode() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw KeychainError.randomFailure
        }
        let value = UInt32(bytes[0]) << 24
            | UInt32(bytes[1]) << 16
            | UInt32(bytes[2]) << 8
            | UInt32(bytes[3])
        let code = String(format: "%06d", value % 1_000_000)
        let data = Data(code.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw KeychainError.writeFailure
        }
        return code
    }

    private static func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.readFailure
        }
        return value
    }

    enum KeychainError: Error {
        case randomFailure
        case readFailure
        case writeFailure
    }
}
