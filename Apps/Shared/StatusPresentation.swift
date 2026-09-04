import Domain
import Foundation
import SwiftUI

enum StatusPresentation {
    static func providerText(
        _ provider: ProviderSnapshot,
        refreshedAt: Date,
        at date: Date,
        locale: Locale = .current
    ) -> String {
        switch provider.availability {
        case .available:
            return updateText(refreshedAt: refreshedAt, at: date, locale: locale)
        case .authenticationRequired:
            return String(localized: "请在 Mac 上重新登录", locale: locale)
        case .temporarilyUnavailable:
            return formatted(
                "%@ 暂时不可用",
                locale: locale,
                provider.displayName
            )
        case .notConfigured:
            return String(localized: "尚未配置", locale: locale)
        case .unsupported:
            return String(localized: "暂不支持", locale: locale)
        }
    }

    static func updateText(
        refreshedAt: Date,
        at date: Date,
        locale: Locale = .current
    ) -> String {
        switch DataUpdateRecency(sourceUpdatedAt: refreshedAt, now: date) {
        case .current:
            return String(localized: "刚刚更新", locale: locale)
        case let .updated(minutesAgo):
            return recentText(minutesAgo: minutesAgo, locale: locale)
        case let .lastUpdated(minutesAgo):
            return lastUpdatedText(minutesAgo: minutesAgo, locale: locale)
        }
    }

    static func unavailableText(
        providerName: String?,
        locale: Locale = .current
    ) -> String {
        guard let providerName, !providerName.isEmpty else {
            return String(localized: "数据源暂时不可用", locale: locale)
        }
        return formatted(
            "%@ 暂时不可用",
            locale: locale,
            providerName
        )
    }

    static func quotaColor(remainingPercent: Double?) -> Color {
        switch RemainingQuotaLevel(remainingPercent: remainingPercent) {
        case .unknown:
            return .secondary
        case .low:
            return .red
        case .reduced:
            return .orange
        case .healthy:
            return .green
        }
    }

    private static func recentText(minutesAgo: Int, locale: Locale) -> String {
        if minutesAgo < 60 {
            return formatted(
                "%lld 分钟前更新",
                locale: locale,
                Int64(minutesAgo)
            )
        }
        if minutesAgo < 24 * 60 {
            return formatted(
                "%lld 小时前更新",
                locale: locale,
                Int64(max(1, minutesAgo / 60))
            )
        }
        return formatted(
            "%lld 天前更新",
            locale: locale,
            Int64(max(1, minutesAgo / (24 * 60)))
        )
    }

    private static func lastUpdatedText(minutesAgo: Int, locale: Locale) -> String {
        if minutesAgo < 60 {
            return formatted(
                "上次更新于 %lld 分钟前",
                locale: locale,
                Int64(minutesAgo)
            )
        }
        if minutesAgo < 24 * 60 {
            return formatted(
                "上次更新于 %lld 小时前",
                locale: locale,
                Int64(max(1, minutesAgo / 60))
            )
        }
        return formatted(
            "上次更新于 %lld 天前",
            locale: locale,
            Int64(max(1, minutesAgo / (24 * 60)))
        )
    }

    private static func formatted(
        _ key: String.LocalizationValue,
        locale: Locale,
        _ arguments: CVarArg...
    ) -> String {
        let format = String(localized: key, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }
}
