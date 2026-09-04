@testable import MacProviderAdapters
import Domain
import Foundation
import Testing

struct CodexQuotaCollectorTests {
    @Test
    func parsesWindowsByDurationAndIncludesCreditAndSpark() throws {
        let fixture = try #require(
            Bundle.module.url(
                forResource: "codex-wham-usage",
                withExtension: "json",
                subdirectory: "Fixtures"
            )
        )
        let windows = try CodexQuotaParser.parse(
            Data(contentsOf: fixture),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(windows.map(\.id) == [
            "codex-primary",
            "codex-secondary",
            "codex-credits",
            "codex-spark-primary",
            "codex-spark-secondary",
        ])
        #expect(windows.map(\.label) == [
            "5 hours",
            "7 days",
            "Credits",
            "Spark 5 hours",
            "Spark 7 days",
        ])
        #expect(windows[0].usedPercent == 12)
        #expect(windows[1].usedPercent == 31)
        #expect(windows[2].usedPercent == 12.5)
        #expect(windows[3].usedPercent == 4)
        #expect(windows[4].usedPercent == 18)
    }

    @Test
    func mapsFreeTierSingleSevenDayWindowToLongLane() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":604800,"reset_at":1900000000},"secondary_window":null}}"#.utf8)
        let windows = try CodexQuotaParser.parse(
            data,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(windows.count == 1)
        #expect(windows.first?.id == "codex-secondary")
        #expect(windows.first?.label == "7 days")
    }

    @Test
    func ignoresMalformedAndExpiredWindows() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":"nope","limit_window_seconds":18000},"secondary_window":{"used_percent":20,"limit_window_seconds":604800,"reset_at":100}}}"#.utf8)
        let windows = try CodexQuotaParser.parse(data, now: Date(timeIntervalSince1970: 200))
        #expect(windows.isEmpty)
    }

    @Test
    func cachedFallbackDropsExpiredWindowsAndOldSnapshots() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let windows = [
            QuotaWindow(
                id: "active",
                label: "5 小时",
                usedPercent: 10,
                resetAt: now.addingTimeInterval(60)
            ),
            QuotaWindow(
                id: "expired",
                label: "7 天",
                usedPercent: 20,
                resetAt: now
            ),
        ]

        #expect(CodexQuotaCollector.usableCachedWindows(
            windows,
            cachedAt: now.addingTimeInterval(-60),
            now: now
        ).map(\.id) == ["active"])
        #expect(CodexQuotaCollector.usableCachedWindows(
            windows,
            cachedAt: now.addingTimeInterval(-(8 * 24 * 60 * 60)),
            now: now
        ).isEmpty)
    }

    @Test
    func sendsAccountHeaderWithoutExposingCredentialInResult() async throws {
        let directory = try temporaryCodexDirectory(
            accessToken: try jwt(accountID: "account-from-jwt")
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = RequestRecorder()
        let collector = CodexQuotaCollector(
            transport: CodexQuotaTransport { request in
                await recorder.record(request)
                return CodexQuotaHTTPResponse(
                    statusCode: 200,
                    data: Data(#"{"rate_limit":{}}"#.utf8)
                )
            }
        )

        let windows = try await collector.fetchWindows(codexDirectory: directory)
        let request = await recorder.request
        #expect(windows.isEmpty)
        #expect(request?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "account-from-jwt")
        #expect(request?.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
    }

    @Test
    func distinguishesMissingAuthAndRejectedAuth() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let unused = CodexQuotaCollector(
            transport: CodexQuotaTransport { _ in
                Issue.record("Transport must not run without auth.json")
                return CodexQuotaHTTPResponse(statusCode: 200, data: Data())
            }
        )
        await #expect(throws: CodexQuotaCollector.CollectorError.notConfigured) {
            try await unused.fetchWindows(codexDirectory: directory)
        }

        let configured = try temporaryCodexDirectory(accessToken: "token")
        defer { try? FileManager.default.removeItem(at: configured) }
        let rejected = CodexQuotaCollector(
            transport: CodexQuotaTransport { _ in
                CodexQuotaHTTPResponse(statusCode: 401, data: Data())
            }
        )
        await #expect(throws: CodexQuotaCollector.CollectorError.authenticationRequired) {
            try await rejected.fetchWindows(codexDirectory: configured)
        }
    }

    private func temporaryCodexDirectory(accessToken: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let auth = ["tokens": ["access_token": accessToken]]
        try JSONSerialization.data(withJSONObject: auth).write(
            to: directory.appending(path: "auth.json")
        )
        return directory
    }

    private func jwt(accountID: String) throws -> String {
        let payload = [
            "https://api.openai.com/auth": ["chatgpt_account_id": accountID],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }
}

private actor RequestRecorder {
    private(set) var request: URLRequest?

    func record(_ request: URLRequest) {
        self.request = request
    }
}
