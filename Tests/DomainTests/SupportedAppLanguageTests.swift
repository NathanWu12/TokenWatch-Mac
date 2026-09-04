import Domain
import Testing

@Suite("Supported app language")
struct SupportedAppLanguageTests {
    @Test("matches common system language identifiers")
    func matchesSystemLanguageIdentifiers() {
        #expect(SupportedAppLanguage.resolve(preferredLanguages: ["en-CN"]) == .english)
        #expect(SupportedAppLanguage.resolve(preferredLanguages: ["ja-JP"]) == .japanese)
        #expect(SupportedAppLanguage.resolve(preferredLanguages: ["ko_KR"]) == .korean)
        #expect(SupportedAppLanguage.resolve(preferredLanguages: ["zh-CN"]) == .simplifiedChinese)
        #expect(SupportedAppLanguage.resolve(preferredLanguages: ["zh-Hant-HK"]) == .traditionalChinese)
        #expect(SupportedAppLanguage.resolve(preferredLanguages: ["pt-BR"]) == .portuguese)
    }

    @Test("uses the first supported preferred language")
    func usesFirstSupportedPreferredLanguage() {
        #expect(
            SupportedAppLanguage.resolve(preferredLanguages: ["ar-SA", "fr-FR", "en-US"])
                == .french
        )
    }

    @Test("falls back to English when the system language is unsupported")
    func fallsBackToEnglish() {
        #expect(SupportedAppLanguage.resolve(preferredLanguages: ["ar-SA"]) == .english)
        #expect(SupportedAppLanguage.resolve(preferredLanguages: []) == .english)
    }

    @Test("stored user choice wins over system preference")
    func storedChoiceWins() {
        #expect(
            SupportedAppLanguage.resolve(
                storedIdentifier: "it",
                preferredLanguages: ["ja-JP"]
            ) == .italian
        )
    }

    @Test("invalid stored choice falls back to system preference")
    func invalidStoredChoiceFallsBack() {
        #expect(
            SupportedAppLanguage.resolve(
                storedIdentifier: "xx",
                preferredLanguages: ["es-MX"]
            ) == .spanish
        )
    }
}
