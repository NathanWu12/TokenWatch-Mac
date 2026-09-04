import Foundation

public enum RetrySchedule {
    public static func delay(
        attempt: Int,
        baseDelay: TimeInterval,
        maximumDelay: TimeInterval,
        jitterFraction: Double,
        jitterUnit: Double
    ) -> TimeInterval {
        let exponent = min(max(0, attempt), 10)
        let backoff = min(maximumDelay, baseDelay * pow(2, Double(exponent)))
        let clampedFraction = min(1, max(0, jitterFraction))
        let clampedUnit = min(1, max(0, jitterUnit))
        return min(
            maximumDelay,
            backoff + backoff * clampedFraction * clampedUnit
        )
    }
}
