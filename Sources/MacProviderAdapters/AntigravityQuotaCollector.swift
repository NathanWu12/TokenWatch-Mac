import Domain
import Foundation

public struct AntigravityQuotaResult: Equatable, Sendable {
    public let windows: [QuotaWindow]
    public let planName: String?

    public init(windows: [QuotaWindow], planName: String?) {
        self.windows = windows
        self.planName = planName
    }
}

public struct AntigravityQuotaCollector: Sendable {
    public enum CollectorError: Error, Equatable {
        case languageServerUnavailable
        case localServiceUnavailable
        case invalidLocalServiceResponse
        case quotaRequestFailed
    }

    public init() {}

    public func fetchQuota(forceRefresh: Bool = false) async throws -> AntigravityQuotaResult {
        let endpoint = try await AntigravityLocalServiceLocator().locate()
        let quotaData = try await request(
            endpoint: endpoint,
            method: "RetrieveUserQuotaSummary",
            body: ["forceRefresh": forceRefresh]
        )
        let windows = try AntigravityQuotaParser.parseQuota(quotaData)

        let planName: String?
        if let planData = try? await request(
            endpoint: endpoint,
            method: "GetLoadCodeAssist",
            body: ["forceRefresh": false]
        ) {
            planName = AntigravityQuotaParser.parsePlanName(planData)
        } else {
            planName = nil
        }
        return AntigravityQuotaResult(windows: windows, planName: planName)
    }

    private func request(
        endpoint: AntigravityLocalServiceEndpoint,
        method: String,
        body: [String: Bool]
    ) async throws -> Data {
        let url = endpoint.baseURL
            .appending(path: "exa.language_server_pb.LanguageServerService")
            .appending(path: method)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(endpoint.csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CollectorError.quotaRequestFailed
        }
        return data
    }
}

struct AntigravityLocalServiceEndpoint: Equatable, Sendable {
    let baseURL: URL
    let csrfToken: String
}

struct AntigravityLocalServiceLocator: Sendable {
    func locate() async throws -> AntigravityLocalServiceEndpoint {
        guard let pid = languageServerPID() else {
            throw AntigravityQuotaCollector.CollectorError.languageServerUnavailable
        }
        for port in listeningPorts(pid: pid) {
            guard let url = URL(string: "http://127.0.0.1:\(port)/") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 1
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let html = String(data: data, encoding: .utf8),
                  let csrfToken = Self.csrfToken(in: html) else {
                continue
            }
            return AntigravityLocalServiceEndpoint(
                baseURL: URL(string: "http://127.0.0.1:\(port)")!,
                csrfToken: csrfToken
            )
        }
        throw AntigravityQuotaCollector.CollectorError.localServiceUnavailable
    }

    private func languageServerPID() -> Int32? {
        let output = Self.run(
            executable: "/usr/bin/pgrep",
            arguments: [
                "-f",
                "/Applications/Antigravity.app/Contents/Resources/bin/language_server",
            ]
        )
        return output?
            .split(whereSeparator: \Character.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .first
    }

    private func listeningPorts(pid: Int32) -> [Int] {
        guard let output = Self.run(
            executable: "/usr/sbin/lsof",
            arguments: ["-Pan", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN"]
        ) else { return [] }
        let regex = try? NSRegularExpression(pattern: #"127\.0\.0\.1:(\d+)"#)
        let range = NSRange(output.startIndex..., in: output)
        let values = regex?.matches(in: output, range: range).compactMap { match -> Int? in
            guard let portRange = Range(match.range(at: 1), in: output) else { return nil }
            return Int(output[portRange])
        } ?? []
        return Array(Set(values)).sorted()
    }

    static func csrfToken(in html: String) -> String? {
        guard let range = html.range(of: #""csrfToken":""#) else { return nil }
        let valueStart = range.upperBound
        guard let valueEnd = html[valueStart...].firstIndex(of: "\"") else { return nil }
        let value = String(html[valueStart..<valueEnd])
        return value.isEmpty ? nil : value
    }

    private static func run(executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

enum AntigravityQuotaParser {
    static func parseQuota(_ data: Data) throws -> [QuotaWindow] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = (root["response"] as? [String: Any]) ?? Optional(root),
              let groups = response["groups"] as? [[String: Any]] else {
            throw AntigravityQuotaCollector.CollectorError.invalidLocalServiceResponse
        }

        return groups.flatMap { group -> [QuotaWindow] in
            let groupName = normalizedString(group["displayName"]) ?? "Antigravity"
            let buckets = group["buckets"] as? [[String: Any]] ?? []
            return buckets.compactMap { bucket in
                guard let remaining = fraction(bucket["remainingFraction"]) else { return nil }
                let bucketID = normalizedString(bucket["bucketId"])
                    ?? normalizedString(bucket["window"])
                    ?? UUID().uuidString
                let window = normalizedString(bucket["window"])
                let bucketName = normalizedString(bucket["displayName"]) ?? "Quota"
                let shortName: String
                switch window?.lowercased() {
                case "weekly": shortName = "Weekly"
                case "5h": shortName = "5 hours"
                default: shortName = bucketName
                }
                return QuotaWindow(
                    id: "antigravity-\(bucketID)",
                    label: "\(groupName) · \(shortName)",
                    usedPercent: (1 - remaining) * 100,
                    resetAt: normalizedString(bucket["resetTime"]).flatMap(parseDate)
                )
            }
        }
    }

    static func parsePlanName(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = (root["response"] as? [String: Any]) ?? Optional(root) else {
            return nil
        }
        if let paidTier = response["paidTier"] as? [String: Any],
           let name = normalizedString(paidTier["name"]) {
            return name
        }
        if let currentTier = response["currentTier"] as? [String: Any] {
            return normalizedString(currentTier["name"])
        }
        return nil
    }

    private static func normalizedString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func fraction(_ value: Any?) -> Double? {
        let number: Double?
        if let value = value as? NSNumber {
            number = value.doubleValue
        } else if let value = value as? String {
            number = Double(value)
        } else {
            number = nil
        }
        guard let number, number.isFinite else { return nil }
        return min(1, max(0, number))
    }

    private static func parseDate(_ value: String) -> Date? {
        return LocalCollectorSupport.parseTimestamp(value)
    }
}
