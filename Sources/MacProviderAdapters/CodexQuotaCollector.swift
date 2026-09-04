import Domain
import Foundation

/// Reads the Codex CLI's existing authentication state and fetches subscription quota windows.
///
/// The credential is used only to authorize the request. It is never returned, persisted, or logged.
/// This adapter is intentionally isolated because the `wham` response is not a public stable API.
public struct CodexQuotaCollector: Sendable {
    public enum CollectorError: Error, Equatable, Sendable {
        case notConfigured
        case invalidAuthenticationFile
        case authenticationRequired
        case unavailableForAccount
        case rateLimited
        case temporarilyUnavailable
        case invalidResponse
    }

    private static let usageEndpoint = "https://chatgpt.com/backend-api/wham/usage"
    private let transport: CodexQuotaTransport

    public init(timeout: TimeInterval = 15) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        transport = CodexQuotaTransport { request in
            var request = request
            request.timeoutInterval = timeout
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CollectorError.invalidResponse
            }
            return CodexQuotaHTTPResponse(
                statusCode: httpResponse.statusCode,
                data: data
            )
        }
    }

    init(transport: CodexQuotaTransport) {
        self.transport = transport
    }

    public func fetchWindows(
        codexDirectory: URL,
        now: Date = Date()
    ) async throws -> [QuotaWindow] {
        let auth = try Self.readAuthentication(from: codexDirectory)
        guard let endpoint = URL(string: Self.usageEndpoint) else {
            throw CollectorError.invalidResponse
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = auth.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let response: CodexQuotaHTTPResponse
        do {
            response = try await transport.fetch(request)
        } catch let error as CollectorError {
            throw error
        } catch {
            throw CollectorError.temporarilyUnavailable
        }

        switch response.statusCode {
        case 200:
            return try CodexQuotaParser.parse(response.data, now: now)
        case 401:
            throw CollectorError.authenticationRequired
        case 403, 404:
            throw CollectorError.unavailableForAccount
        case 429:
            throw CollectorError.rateLimited
        default:
            throw CollectorError.temporarilyUnavailable
        }
    }

    public static func usableCachedWindows(
        _ windows: [QuotaWindow],
        cachedAt: Date?,
        now: Date,
        maximumAge: TimeInterval = 7 * 24 * 60 * 60
    ) -> [QuotaWindow] {
        guard let cachedAt,
              cachedAt <= now.addingTimeInterval(60),
              now.timeIntervalSince(cachedAt) <= maximumAge else {
            return []
        }
        return windows.filter { $0.resetAt.map { $0 > now } ?? true }
    }

    private static func readAuthentication(from directory: URL) throws -> CodexAuthentication {
        let url = directory.appending(path: "auth.json", directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CollectorError.notConfigured
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw CollectorError.invalidAuthenticationFile
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let accessToken = normalizedString(tokens["access_token"]) else {
            throw CollectorError.invalidAuthenticationFile
        }
        let accountID = normalizedString(tokens["account_id"])
            ?? accountIDFromJWT(accessToken)
            ?? normalizedString(tokens["id_token"]).flatMap(accountIDFromJWT)
        return CodexAuthentication(accessToken: accessToken, accountID: accountID)
    }

    private static func normalizedString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func accountIDFromJWT(_ token: String) -> String? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let namespace = object["https://api.openai.com/auth"] as? [String: Any] else {
            return nil
        }
        return normalizedString(namespace["chatgpt_account_id"])
    }
}

struct CodexQuotaTransport: Sendable {
    let fetch: @Sendable (URLRequest) async throws -> CodexQuotaHTTPResponse

    init(fetch: @escaping @Sendable (URLRequest) async throws -> CodexQuotaHTTPResponse) {
        self.fetch = fetch
    }
}

struct CodexQuotaHTTPResponse: Sendable {
    let statusCode: Int
    let data: Data
}

private struct CodexAuthentication: Sendable {
    let accessToken: String
    let accountID: String?
}

enum CodexQuotaParser {
    private static let sessionWindowSeconds = 18_000
    private static let weeklyWindowSeconds = 604_800

    static func parse(_ data: Data, now: Date) throws -> [QuotaWindow] {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexQuotaCollector.CollectorError.invalidResponse
        }

        var windows: [QuotaWindow] = []
        if let rateLimit = body["rate_limit"] as? [String: Any] {
            let normalized = normalizeRateWindows(rateLimit)
            if let session = normalized.session {
                windows.append(makeWindow(id: "codex-primary", label: "5 hours", raw: session))
            }
            if let weekly = normalized.weekly {
                windows.append(makeWindow(id: "codex-secondary", label: "7 days", raw: weekly))
            }
        }

        if let credit = creditWindow(body) {
            windows.append(credit)
        }
        windows.append(contentsOf: sparkWindows(body))

        return windows.filter { window in
            guard let resetAt = window.resetAt else { return true }
            return resetAt > now.addingTimeInterval(-60)
        }
    }

    private static func normalizeRateWindows(
        _ rateLimit: [String: Any]
    ) -> (session: [String: Any]?, weekly: [String: Any]?) {
        let primary = normalizedWindow(rateLimit["primary_window"])
        let secondary = normalizedWindow(rateLimit["secondary_window"])
        let candidates = [primary, secondary].compactMap { $0 }
        var session = candidates.first { duration($0) == sessionWindowSeconds }
        var weekly = candidates.first { duration($0) == weeklyWindowSeconds }

        // Preserve unexpected server shapes positionally only when neither duration is known.
        if session == nil, weekly == nil, !candidates.isEmpty {
            session = primary
            weekly = secondary
        }
        return (session, weekly)
    }

    private static func normalizedWindow(_ value: Any?) -> [String: Any]? {
        guard let raw = value as? [String: Any], percent(raw["used_percent"]) != nil else {
            return nil
        }
        return raw
    }

    private static func makeWindow(
        id: String,
        label: String,
        raw: [String: Any]
    ) -> QuotaWindow {
        QuotaWindow(
            id: id,
            label: label,
            usedPercent: percent(raw["used_percent"])?.rounded(),
            resetAt: date(raw["reset_at"])
        )
    }

    private static func sparkWindows(_ body: [String: Any]) -> [QuotaWindow] {
        guard let limits = body["additional_rate_limits"] as? [Any] else { return [] }
        for case let entry as [String: Any] in limits {
            let names = [entry["limit_name"], entry["metered_feature"]]
                .compactMap { $0 as? String }
            guard names.contains(where: { $0.localizedCaseInsensitiveContains("spark") }),
                  let rateLimit = entry["rate_limit"] as? [String: Any] else {
                continue
            }
            let normalized = normalizeRateWindows(rateLimit)
            return [
                normalized.session.map {
                    makeWindow(id: "codex-spark-primary", label: "Spark 5 hours", raw: $0)
                },
                normalized.weekly.map {
                    makeWindow(id: "codex-spark-secondary", label: "Spark 7 days", raw: $0)
                },
            ].compactMap { $0 }
        }
        return []
    }

    private static func creditWindow(_ body: [String: Any]) -> QuotaWindow? {
        guard let spendControl = body["spend_control"] as? [String: Any],
              let limit = spendControl["individual_limit"] as? [String: Any] else {
            return nil
        }
        let limitCredits = number(limit["limit"])
        let usedCredits = number(limit["used"])
        var usedPercent = percent(limit["used_percent"])
        if let limitCredits, limitCredits > 0, let usedCredits,
           usedPercent == nil || (usedPercent == 0 && usedCredits > 0) {
            usedPercent = min(100, max(0, usedCredits / limitCredits * 100))
        }
        guard let usedPercent else { return nil }
        return QuotaWindow(
            id: "codex-credits",
            label: "Credits",
            usedPercent: usedPercent,
            resetAt: date(limit["reset_at"])
        )
    }

    private static func duration(_ raw: [String: Any]) -> Int? {
        number(raw["limit_window_seconds"]).map { Int($0) }
    }

    private static func percent(_ value: Any?) -> Double? {
        number(value).map { min(100, max(0, $0)) }
    }

    private static func number(_ value: Any?) -> Double? {
        let result: Double?
        switch value {
        case let number as NSNumber: result = number.doubleValue
        case let string as String: result = Double(string)
        default: result = nil
        }
        guard let result, result.isFinite else { return nil }
        return result
    }

    private static func date(_ value: Any?) -> Date? {
        if let seconds = number(value), seconds > 0 {
            return Date(timeIntervalSince1970: seconds)
        }
        guard let text = value as? String else { return nil }
        return LocalCollectorSupport.parseTimestamp(text)
    }
}
