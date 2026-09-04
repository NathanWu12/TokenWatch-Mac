import Foundation

public enum SupportedAppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case portuguese = "pt"
    case italian = "it"
    case russian = "ru"
    case dutch = "nl"

    public var id: String { rawValue }

    public var locale: Locale {
        Locale(identifier: rawValue)
    }

    public var nativeDisplayName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        case .portuguese: "Português"
        case .italian: "Italiano"
        case .russian: "Русский"
        case .dutch: "Nederlands"
        }
    }

    public static var systemDefault: SupportedAppLanguage {
        resolve(preferredLanguages: Locale.preferredLanguages)
    }

    public static func resolve(
        storedIdentifier: String?,
        preferredLanguages: [String]
    ) -> SupportedAppLanguage {
        if let storedIdentifier,
           let storedLanguage = SupportedAppLanguage(rawValue: storedIdentifier) {
            return storedLanguage
        }
        return resolve(preferredLanguages: preferredLanguages)
    }

    public static func resolve(
        preferredLanguages: [String]
    ) -> SupportedAppLanguage {
        for identifier in preferredLanguages {
            if let language = resolve(identifier: identifier) {
                return language
            }
        }
        return .english
    }

    private static func resolve(identifier: String) -> SupportedAppLanguage? {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        let components = normalized.split(separator: "-").map(String.init)
        guard let languageCode = components.first else { return nil }

        if languageCode == "zh" {
            if components.contains("hant")
                || components.contains("tw")
                || components.contains("hk")
                || components.contains("mo") {
                return .traditionalChinese
            }
            return .simplifiedChinese
        }

        switch languageCode {
        case "en": return .english
        case "ja": return .japanese
        case "ko": return .korean
        case "es": return .spanish
        case "fr": return .french
        case "de": return .german
        case "pt": return .portuguese
        case "it": return .italian
        case "ru": return .russian
        case "nl": return .dutch
        default: return nil
        }
    }
}
