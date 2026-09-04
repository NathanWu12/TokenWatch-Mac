@testable import MacProviderAdapters
import Foundation
import Testing

@Suite("Antigravity quota collector")
struct AntigravityQuotaCollectorTests {
    @Test("parses grouped weekly and five-hour quota windows")
    func parsesQuota() throws {
        let data = Data(#"{"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"gemini-weekly","displayName":"Weekly Limit Remaining","remainingFraction":0.75,"resetTime":"2026-09-10T18:30:39Z","window":"weekly"},{"bucketId":"gemini-5h","displayName":"Five Hour Limit Remaining","remainingFraction":0.4,"resetTime":"2026-09-03T23:30:39Z","window":"5h"}]},{"displayName":"Claude and GPT models","buckets":[{"bucketId":"3p-weekly","displayName":"Weekly Limit Remaining","remainingFraction":1,"window":"weekly"}]}]}}"#.utf8)
        let windows = try AntigravityQuotaParser.parseQuota(data)

        #expect(windows.map(\.id) == ["antigravity-gemini-weekly", "antigravity-gemini-5h", "antigravity-3p-weekly"])
        #expect(windows.map(\.label) == ["Gemini Models · Weekly", "Gemini Models · 5 hours", "Claude and GPT models · Weekly"])
        #expect(windows.map(\.usedPercent) == [25, 60, 0])
        #expect(windows[0].resetAt != nil)
    }

    @Test("parses paid plan name")
    func parsesPlan() {
        let data = Data(#"{"response":{"currentTier":{"name":"Antigravity"},"paidTier":{"name":"Google AI Pro"}}}"#.utf8)
        #expect(AntigravityQuotaParser.parsePlanName(data) == "Google AI Pro")
    }

    @Test("extracts only the local service csrf token from bootstrap html")
    func extractsCSRF() {
        let html = #"<script>window.__APP_CONFIG__={"productName":"antigravity","csrfToken":"local-only-value"};</script>"#
        #expect(AntigravityLocalServiceLocator.csrfToken(in: html) == "local-only-value")
    }
}
