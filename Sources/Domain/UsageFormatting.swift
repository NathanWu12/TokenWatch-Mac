import Foundation

public enum UsageFormatting {
    public static func compactTokens(_ value: Int64, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1

        let absolute = Double(Swift.abs(value))
        let sign = value < 0 ? "-" : ""
        let divisor: Double
        let suffix: String
        switch absolute {
        case 1_000_000_000...:
            divisor = 1_000_000_000
            suffix = "B"
        case 1_000_000...:
            divisor = 1_000_000
            suffix = "M"
        case 1_000...:
            divisor = 1_000
            suffix = "K"
        default:
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }
        let formatted = formatter.string(from: NSNumber(value: absolute / divisor)) ?? "0"
        return "\(sign)\(formatted)\(suffix)"
    }
    public static func compactTokens(
        _ value: Int64,
        estimated: Bool,
        locale: Locale = .current
    ) -> String {
        let formatted = compactTokens(value, locale: locale)
        return estimated ? "~\(formatted)" : formatted
    }

}
