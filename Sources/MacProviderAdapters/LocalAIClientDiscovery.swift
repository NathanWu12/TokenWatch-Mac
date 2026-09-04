import Foundation

/// AI coding clients whose local usage stores TokenWatch can discover without
/// walking unrelated user files.
public enum LocalAIClient: String, CaseIterable, Hashable, Identifiable, Sendable {
    case codex
    case claudeCode = "claude-code"
    case antigravity
    case openCode = "opencode"

    public var id: String { rawValue }

    /// A missing persisted value means the feature has never been configured,
    /// so every supported client starts enabled. Once saved, only known IDs are used.
    public static func enabledClients(fromStoredRawValues rawValues: [String]?) -> Set<Self> {
        guard let rawValues else { return Set(allCases) }
        return Set(rawValues.compactMap(Self.init(rawValue:)))
    }

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .antigravity: "Antigravity"
        case .openCode: "OpenCode"
        }
    }
}

public struct LocalAIClientLocation: Identifiable, Equatable, Sendable {
    public let client: LocalAIClient
    public let rootDirectory: URL

    public init(client: LocalAIClient, rootDirectory: URL) {
        self.client = client
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    public var id: String {
        "\(client.rawValue):\(rootDirectory.path(percentEncoded: false))"
    }
}

/// Resolves only known provider data roots. It intentionally does not scan the
/// user's home directory recursively and never opens auth/credential files.
public struct LocalAIClientDiscovery {
    private let homeDirectory: URL
    private let environment: [String: String]
    private let fileManager: FileManager

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.environment = environment
        self.fileManager = fileManager
    }

    public func discover() -> [LocalAIClientLocation] {
        var result: [LocalAIClientLocation] = []
        result.append(contentsOf: existingLocations(.codex, candidates: codexCandidates()))
        result.append(contentsOf: existingLocations(.claudeCode, candidates: claudeCandidates()))
        result.append(contentsOf: existingLocations(.antigravity, candidates: antigravityCandidates()))
        result.append(contentsOf: existingLocations(.openCode, candidates: openCodeCandidates()))
        return deduplicated(result)
    }

    public func locations(for client: LocalAIClient) -> [LocalAIClientLocation] {
        discover().filter { $0.client == client }
    }

    private func codexCandidates() -> [URL] {
        compactPaths([
            environment["CODEX_HOME"],
            homeDirectory.appending(path: ".codex", directoryHint: .isDirectory).path,
        ])
    }

    private func claudeCandidates() -> [URL] {
        compactPaths([
            environment["CLAUDE_CONFIG_DIR"],
            homeDirectory.appending(path: ".claude", directoryHint: .isDirectory).path,
        ])
    }

    private func antigravityCandidates() -> [URL] {
        let geminiRoot = homeDirectory
            .appending(path: ".gemini", directoryHint: .isDirectory)
        var candidates = [
            geminiRoot.appending(path: "antigravity", directoryHint: .isDirectory),
            geminiRoot.appending(path: "antigravity-cli", directoryHint: .isDirectory),
        ]

        if let children = try? fileManager.contentsOfDirectory(
            at: geminiRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: children.filter { url in
                guard url.lastPathComponent.lowercased().hasPrefix("antigravity") else {
                    return false
                }
                return isDirectory(url)
            })
        }
        return candidates
    }

    private func openCodeCandidates() -> [URL] {
        var paths: [String?] = [environment["OPENCODE_DATA_DIR"]]
        if let xdg = environment["XDG_DATA_HOME"], !xdg.isEmpty {
            paths.append(
                URL(fileURLWithPath: xdg, isDirectory: true)
                    .appending(path: "opencode", directoryHint: .isDirectory)
                    .path
            )
        }
        paths.append(
            homeDirectory
                .appending(path: ".local/share/opencode", directoryHint: .isDirectory)
                .path
        )
        return compactPaths(paths)
    }

    private func existingLocations(
        _ client: LocalAIClient,
        candidates: [URL]
    ) -> [LocalAIClientLocation] {
        candidates.compactMap { candidate in
            guard isDirectory(candidate) else { return nil }
            return LocalAIClientLocation(client: client, rootDirectory: candidate)
        }
    }

    private func compactPaths(_ paths: [String?]) -> [URL] {
        paths.compactMap { value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func deduplicated(_ values: [LocalAIClientLocation]) -> [LocalAIClientLocation] {
        var seen = Set<String>()
        return values.filter { value in
            seen.insert(value.id).inserted
        }
    }
}
