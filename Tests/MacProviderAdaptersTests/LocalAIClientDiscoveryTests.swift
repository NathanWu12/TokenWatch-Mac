import Foundation
import MacProviderAdapters
import Testing

@Suite("Local AI client discovery")
struct LocalAIClientDiscoveryTests {
    @Test("discovers only known provider roots")
    func discoversKnownRoots() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        try makeDirectory(home.appending(path: ".codex"))
        try makeDirectory(home.appending(path: ".claude/projects"))
        try makeDirectory(home.appending(path: ".gemini/antigravity/brain"))
        try makeDirectory(home.appending(path: ".gemini/antigravity-cli/brain"))
        try makeDirectory(home.appending(path: ".local/share/opencode"))
        try makeDirectory(home.appending(path: "unrelated-ai-client"))

        let discovered = LocalAIClientDiscovery(
            homeDirectory: home,
            environment: [:]
        ).discover()

        #expect(Set(discovered.map(\.client)) == Set(LocalAIClient.allCases))
        #expect(discovered.filter { $0.client == .antigravity }.count == 2)
        #expect(discovered.allSatisfy { !$0.rootDirectory.path.contains("unrelated-ai-client") })
    }

    @Test("environment overrides are considered before defaults")
    func honorsOverrides() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let customCodex = home.appending(path: "custom-codex")
        let customClaude = home.appending(path: "custom-claude")
        let xdg = home.appending(path: "xdg")
        try makeDirectory(customCodex)
        try makeDirectory(customClaude)
        try makeDirectory(xdg.appending(path: "opencode"))

        let discovered = LocalAIClientDiscovery(
            homeDirectory: home,
            environment: [
                "CODEX_HOME": customCodex.path,
                "CLAUDE_CONFIG_DIR": customClaude.path,
                "XDG_DATA_HOME": xdg.path,
            ]
        ).discover()

        #expect(
            discovered.first(where: { $0.client == .codex })?.rootDirectory.path
                == customCodex.standardizedFileURL.path
        )
        #expect(
            discovered.first(where: { $0.client == .claudeCode })?.rootDirectory.path
                == customClaude.standardizedFileURL.path
        )
        #expect(
            discovered.first(where: { $0.client == .openCode })?.rootDirectory.path
                == xdg.appending(path: "opencode").standardizedFileURL.path
        )
    }

    @Test("all clients are enabled until a preference is explicitly saved")
    func defaultsAllClientsEnabled() {
        #expect(LocalAIClient.enabledClients(fromStoredRawValues: nil) == Set(LocalAIClient.allCases))
    }

    @Test("an explicitly saved empty list keeps every client disabled")
    func restoresAllClientsDisabled() {
        #expect(LocalAIClient.enabledClients(fromStoredRawValues: []) == [])
    }

    @Test("saved client enablement ignores unknown provider IDs")
    func restoresEnabledClients() {
        let enabled = LocalAIClient.enabledClients(
            fromStoredRawValues: ["codex", "opencode", "future-provider"]
        )
        #expect(enabled == Set([.codex, .openCode]))
    }

    @Test("missing roots are not reported")
    func ignoresMissingRoots() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let discovered = LocalAIClientDiscovery(
            homeDirectory: home,
            environment: [:]
        ).discover()

        #expect(discovered.isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "tokenwatch-discovery-\(UUID().uuidString)", directoryHint: .isDirectory)
        try makeDirectory(url)
        return url
    }

    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }
}
